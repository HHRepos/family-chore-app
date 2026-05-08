import { APIGatewayProxyEvent, APIGatewayProxyResult } from 'aws-lambda';
import { Pool } from 'pg';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { v4 as uuidv4 } from 'uuid';
import { voiceOnboarding, getInitialGreeting, analyzeRoomImage, textToSpeechAudio, aiDistributeChores } from './services/openai';

// In-memory session store for conversation history (in production, use Redis/DynamoDB)
const conversationSessions: Map<string, Array<{ role: 'user' | 'assistant'; content: string }>> = new Map();

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key';

const headers = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type,Authorization',
  'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS'
};

const response = (statusCode: number, body: any): APIGatewayProxyResult => ({
  statusCode,
  headers,
  body: JSON.stringify(body)
});

// Format a postgres DATE value as a YYYY-MM-DD string without ever
// passing through `new Date(...).toISOString()`, which is fragile when
// the runtime TZ is not UTC (the date can shift by a day). pg returns
// DATE columns as JS Date objects parsed at UTC midnight by default —
// pull the parts off in UTC.
const dateOnly = (d: any): string | null => {
  if (d == null) return null;
  if (typeof d === 'string') return d.slice(0, 10);
  if (d instanceof Date) {
    const y = d.getUTCFullYear();
    const m = String(d.getUTCMonth() + 1).padStart(2, '0');
    const day = String(d.getUTCDate()).padStart(2, '0');
    return `${y}-${m}-${day}`;
  }
  return String(d);
};

// Format a postgres TIMESTAMP / TIMESTAMPTZ as ISO 8601 with timezone.
const isoOrNull = (d: any): string | null => {
  if (d == null) return null;
  if (typeof d === 'string') return d;
  if (d instanceof Date) return d.toISOString();
  return null;
};

const getUserFromToken = (event: APIGatewayProxyEvent) => {
  const authHeader = event.headers?.Authorization || event.headers?.authorization;
  if (!authHeader) return null;
  const token = authHeader.replace('Bearer ', '');
  try {
    return jwt.verify(token, JWT_SECRET) as { userId: string; email: string; role: string };
  } catch {
    return null;
  }
};

export const handler = async (event: any): Promise<APIGatewayProxyResult> => {
  // Support both REST API v1 and HTTP API v2 event formats
  const httpMethod = event.httpMethod || event.requestContext?.http?.method;
  const path = event.path || event.rawPath;

  // Handle base64 encoded body in HTTP API v2
  let bodyStr = event.body;
  if (event.isBase64Encoded && bodyStr) {
    bodyStr = Buffer.from(bodyStr, 'base64').toString('utf-8');
  }
  let data: any = {};
  if (bodyStr) {
    try {
      data = JSON.parse(bodyStr);
    } catch {
      // Body might be base64 even without isBase64Encoded flag
      try {
        data = JSON.parse(Buffer.from(bodyStr, 'base64').toString('utf-8'));
      } catch {
        console.error('Failed to parse body:', bodyStr.substring(0, 100));
        data = {};
      }
    }
  }

  // Handle CORS preflight
  if (httpMethod === 'OPTIONS') {
    return response(200, {});
  }

  try {
    // Auth routes
    if (path === '/v1/auth/register' && httpMethod === 'POST') {
      const { email, password, first_name, last_name, role: requestedRole } = data;

      const existing = await pool.query('SELECT user_id FROM users WHERE email = $1', [email]);
      if (existing.rows.length > 0) {
        return response(409, { error: 'User already exists' });
      }

      const passwordHash = await bcrypt.hash(password, 10);
      const userId = uuidv4();
      const userRole = requestedRole === 'child' ? 'child' : 'parent'; // default parent, allow child

      await pool.query(
        `INSERT INTO users (user_id, email, password_hash, first_name, last_name, role)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [userId, email, passwordHash, first_name, last_name, userRole]
      );

      const token = jwt.sign({ userId, email, role: userRole }, JWT_SECRET, { expiresIn: '7d' });
      return response(201, { user_id: userId, email, token });
    }

    if (path === '/v1/auth/login' && httpMethod === 'POST') {
      const { email, password } = data;

      const result = await pool.query(
        'SELECT user_id, email, password_hash, first_name, last_name, role, family_id FROM users WHERE email = $1',
        [email]
      );

      if (result.rows.length === 0) {
        return response(401, { error: 'Invalid credentials' });
      }

      const user = result.rows[0];
      const valid = await bcrypt.compare(password, user.password_hash);
      if (!valid) {
        return response(401, { error: 'Invalid credentials' });
      }

      const token = jwt.sign({ userId: user.user_id, email, role: user.role }, JWT_SECRET, { expiresIn: '7d' });
      return response(200, { user_id: user.user_id, email, token });
    }

    if (path === '/v1/auth/profile' && httpMethod === 'GET') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const result = await pool.query(
        `SELECT user_id, email, first_name, last_name, role, family_id,
                COALESCE(avatar_customizations, ARRAY[]::TEXT[]) AS avatar_customizations
           FROM users WHERE user_id = $1`,
        [user.userId]
      );

      if (result.rows.length === 0) return response(404, { error: 'User not found' });
      const u = result.rows[0];
      return response(200, {
        user_id: u.user_id,
        email: u.email,
        first_name: u.first_name,
        last_name: u.last_name,
        role: u.role,
        family_id: u.family_id,
        avatar_customizations: u.avatar_customizations
      });
    }

    // Avatar customization — `customizations` is an array of "key:value" pairs
    // the iOS AvatarView appends to the DiceBear URL. Auth: the user can edit
    // their own avatar; a parent in the same family can edit any child's.
    if (path.match(/^\/v1\/users\/[^/]+\/avatar$/) && httpMethod === 'PATCH') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const targetUserId = path.split('/')[3];
      const { customizations } = data;
      if (!Array.isArray(customizations)) {
        return response(400, { error: 'customizations must be an array of strings' });
      }
      // Sanitize: each item must be `key:value`, no nasties.
      const safe = customizations
        .filter((c: unknown): c is string => typeof c === 'string' && /^[a-zA-Z0-9_]+:[a-zA-Z0-9_,#\-]+$/.test(c))
        .slice(0, 20);

      // Permission: self, or a parent in the same family.
      if (targetUserId !== user.userId) {
        const ok = await pool.query(
          `SELECT 1
             FROM users me
             JOIN family_members mfm ON me.user_id = mfm.user_id
             JOIN family_members tfm ON tfm.user_id = $1 AND tfm.family_id = mfm.family_id
            WHERE me.user_id = $2 AND me.role = 'parent'`,
          [targetUserId, user.userId]
        );
        if (ok.rows.length === 0) return response(403, { error: 'Not allowed to edit this avatar' });
      }

      await pool.query(
        'UPDATE users SET avatar_customizations = $1 WHERE user_id = $2',
        [safe, targetUserId]
      );
      return response(200, { user_id: targetUserId, avatar_customizations: safe });
    }

    // Family routes
    if (path === '/v1/families' && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const { family_name, house_type } = data;
      const familyId = uuidv4();

      await pool.query(
        `INSERT INTO families (family_id, family_name, house_type, created_by) VALUES ($1, $2, $3, $4)`,
        [familyId, family_name, house_type, user.userId]
      );

      await pool.query('UPDATE users SET family_id = $1 WHERE user_id = $2', [familyId, user.userId]);
      await pool.query(
        `INSERT INTO family_members (family_id, user_id, role) VALUES ($1, $2, 'parent')`,
        [familyId, user.userId]
      );

      // Generate a 6-char family code
      const familyCode = familyId.replace(/-/g, '').substring(0, 6).toUpperCase();
      await pool.query('UPDATE families SET family_code = $1 WHERE family_id = $2', [familyCode, familyId]);

      return response(201, { family_id: familyId, family_name, family_code: familyCode });
    }

    // Join a family by code
    if (path === '/v1/families/join' && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const { family_code, role } = data;
      if (!family_code) return response(400, { error: 'family_code is required' });

      const familyResult = await pool.query(
        'SELECT family_id, family_name, family_code FROM families WHERE UPPER(family_code) = UPPER($1)',
        [family_code]
      );
      if (familyResult.rows.length === 0) return response(404, { error: 'Family not found. Check the code and try again.' });

      const family = familyResult.rows[0];

      // Check not already a member
      const existing = await pool.query(
        'SELECT 1 FROM family_members WHERE family_id = $1 AND user_id = $2',
        [family.family_id, user.userId]
      );
      if (existing.rows.length > 0) return response(400, { error: 'You are already in this family' });

      const memberRole = role === 'parent' ? 'parent' : 'child';
      await pool.query('UPDATE users SET family_id = $1, role = $2 WHERE user_id = $3', [family.family_id, memberRole, user.userId]);
      await pool.query(
        'INSERT INTO family_members (family_id, user_id, role) VALUES ($1, $2, $3)',
        [family.family_id, user.userId, memberRole]
      );

      return response(200, { message: 'Joined family!', family_id: family.family_id, family_name: family.family_name });
    }

    if (path.match(/^\/v1\/families\/[^/]+$/) && httpMethod === 'GET') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const familyId = path.split('/')[3];
      const familyResult = await pool.query(
        'SELECT family_id, family_name, house_type, house_details, family_code FROM families WHERE family_id = $1',
        [familyId]
      );

      if (familyResult.rows.length === 0) return response(404, { error: 'Family not found' });

      const membersResult = await pool.query(
        `SELECT u.user_id, u.first_name, u.role, u.age, u.email,
                COALESCE(u.participate_in_chores, false) AS participate_in_chores,
                COALESCE(u.avatar_customizations, ARRAY[]::TEXT[]) AS avatar_customizations,
                fm.nickname
         FROM users u JOIN family_members fm ON u.user_id = fm.user_id
         WHERE fm.family_id = $1`,
        [familyId]
      );

      const family = familyResult.rows[0];
      return response(200, {
        family_id: family.family_id,
        family_name: family.family_name,
        family_code: family.family_code,
        house_details: family.house_details || {},
        members: membersResult.rows.map(m => ({
          user_id: m.user_id,
          first_name: m.first_name,
          nickname: m.nickname,
          role: m.role,
          age: m.age,
          hasAccount: !!m.email,
          participates: m.participate_in_chores,
          avatar_customizations: m.avatar_customizations
        }))
      });
    }

    // Update family config (bin schedule, pets, gaming schedule)
    if (path.match(/^\/v1\/families\/[^/]+\/config$/) && httpMethod === 'PATCH') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const familyId = path.split('/')[3];
      const { bin_schedule, pets, gaming_schedule } = data;

      // Read current house_details
      const current = await pool.query('SELECT house_details FROM families WHERE family_id = $1', [familyId]);
      if (current.rows.length === 0) return response(404, { error: 'Family not found' });

      const details = current.rows[0].house_details || {};

      // Merge only provided keys
      if (bin_schedule !== undefined) details.bin_schedule = bin_schedule;
      if (pets !== undefined) details.pets = pets;
      if (gaming_schedule !== undefined) details.gaming_schedule = gaming_schedule;

      await pool.query('UPDATE families SET house_details = $1 WHERE family_id = $2', [JSON.stringify(details), familyId]);

      return response(200, { house_details: details });
    }

    if (path.match(/^\/v1\/families\/[^/]+\/members$/) && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const familyId = path.split('/')[3];
      const { first_name, nickname, age, emoji } = data;
      const userId = uuidv4();

      await pool.query(
        `INSERT INTO users (user_id, first_name, role, family_id, age, emoji)
         VALUES ($1, $2, 'child', $3, $4, $5)`,
        [userId, first_name, familyId, age, emoji || null]
      );

      await pool.query(
        `INSERT INTO family_members (family_id, user_id, role, nickname)
         VALUES ($1, $2, 'child', $3)`,
        [familyId, userId, nickname || first_name]
      );

      return response(201, { user_id: userId, first_name, nickname: nickname || first_name });
    }

    // Chores routes
    if (path.match(/^\/v1\/users\/[^/]+\/chores$/) && httpMethod === 'GET') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const userId = path.split('/')[3];
      const result = await pool.query(
        `SELECT ac.*, c.chore_name, c.description, c.points, c.difficulty, c.chore_type, c.time_of_day, c.min_age, c.auto_approve
         FROM assigned_chores ac
         JOIN chores c ON ac.chore_id = c.chore_id
         WHERE ac.user_id = $1
         ORDER BY ac.due_date ASC`,
        [userId]
      );

      return response(200, result.rows.map(r => ({
        assignedChoreId: r.assigned_chore_id,
        choreId: r.chore_id,
        userId: r.user_id,
        dueDate: dateOnly(r.due_date),
        status: r.status,
        choreName: r.chore_name,
        description: r.description,
        points: r.points,
        difficulty: r.difficulty,
        choreType: r.chore_type || 'household',
        timeOfDay: r.time_of_day || 'anytime',
        minAge: r.min_age || 3,
        autoApprove: !!r.auto_approve
      })));
    }

    // Get user stats: total completed, streak, total points
    if (path.match(/^\/v1\/users\/[^/]+\/stats$/) && httpMethod === 'GET') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const userId = path.split('/')[3];

      // Total completed (all time)
      const totalResult = await pool.query(
        `SELECT COUNT(*) as total FROM assigned_chores
         WHERE user_id = $1 AND status IN ('completed', 'approved')`,
        [userId]
      );

      // This week completed
      const now = new Date();
      const dayOfWeek = now.getDay();
      const mondayOffset = dayOfWeek === 0 ? -6 : 1 - dayOfWeek;
      const weekStart = new Date(now);
      weekStart.setDate(now.getDate() + mondayOffset);
      const weekStartStr = weekStart.toISOString().split('T')[0];

      const weekResult = await pool.query(
        `SELECT COUNT(*) as total FROM assigned_chores
         WHERE user_id = $1 AND status IN ('completed', 'approved') AND due_date >= $2`,
        [userId, weekStartStr]
      );

      // Streak: consecutive days with all chores completed (going backwards from yesterday)
      const streakResult = await pool.query(
        `SELECT due_date,
                COUNT(*) as total,
                COUNT(*) FILTER (WHERE status IN ('completed', 'approved')) as done
         FROM assigned_chores
         WHERE user_id = $1 AND due_date < CURRENT_DATE
         GROUP BY due_date
         ORDER BY due_date DESC
         LIMIT 60`,
        [userId]
      );

      let streak = 0;
      const yesterday = new Date(now);
      yesterday.setDate(now.getDate() - 1);
      let checkDate = new Date(yesterday);

      for (const row of streakResult.rows) {
        const rowDate = new Date(row.due_date).toISOString().split('T')[0];
        const expectedDate = checkDate.toISOString().split('T')[0];

        if (rowDate !== expectedDate) break; // gap in dates
        if (parseInt(row.total) > 0 && parseInt(row.total) === parseInt(row.done)) {
          streak++;
          checkDate.setDate(checkDate.getDate() - 1);
        } else {
          break;
        }
      }

      // Total points
      const pointsResult = await pool.query(
        'SELECT COALESCE(points, 0) as points FROM users WHERE user_id = $1', [userId]
      );

      return response(200, {
        totalCompleted: parseInt(totalResult.rows[0].total),
        weekCompleted: parseInt(weekResult.rows[0].total),
        streak,
        totalPoints: pointsResult.rows[0]?.points || 0,
      });
    }

    if (path.match(/^\/v1\/chores\/assigned\/[^/]+$/) && httpMethod === 'PATCH') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const assignedChoreId = path.split('/')[4];
      const { status } = data;

      let query = 'UPDATE assigned_chores SET status = $1';
      const params: any[] = [status];
      if (status === 'completed') query += ', completed_at = NOW()';
      query += ' WHERE assigned_chore_id = $' + (params.length + 1) + ' RETURNING *';
      params.push(assignedChoreId);

      const result = await pool.query(query, params);
      const updated = result.rows[0];
      if (!updated) return response(404, { error: 'Chore not found' });

      // If the chore is auto-approve and the child just marked it complete,
      // skip the parent-review step: flip to `approved` and award points
      // atomically. Points come back in the response so the iOS app can
      // animate the counter without a refresh round-trip.
      if (status === 'completed') {
        const choreMeta = await pool.query(
          `SELECT c.auto_approve, c.points
             FROM assigned_chores ac
             JOIN chores c ON ac.chore_id = c.chore_id
            WHERE ac.assigned_chore_id = $1`,
          [assignedChoreId]
        );
        if (choreMeta.rows[0]?.auto_approve) {
          const transition = await pool.query(
            `UPDATE assigned_chores
                SET status = 'approved', approved_at = NOW()
              WHERE assigned_chore_id = $1 AND status <> 'approved'
            RETURNING user_id, transferred_from, transfer_type, original_points`,
            [assignedChoreId]
          );
          if (transition.rows.length > 0) {
            const row = transition.rows[0];
            const pointsValue = row.original_points ?? choreMeta.rows[0].points ?? 0;
            if (row.transfer_type === 'support' && row.transferred_from) {
              const half = Math.ceil(pointsValue / 2);
              await pool.query('UPDATE users SET points = COALESCE(points,0) + $1 WHERE user_id = $2', [half, row.user_id]);
              await pool.query('UPDATE users SET points = COALESCE(points,0) + $1 WHERE user_id = $2', [half, row.transferred_from]);
              return response(200, { ...updated, status: 'approved', autoApproved: true, pointsAwarded: half, splitWith: row.transferred_from });
            }
            await pool.query('UPDATE users SET points = COALESCE(points,0) + $1 WHERE user_id = $2', [pointsValue, row.user_id]);
            return response(200, { ...updated, status: 'approved', autoApproved: true, pointsAwarded: pointsValue });
          }
        }
      }

      return response(200, updated);
    }

    if (path.match(/^\/v1\/chores\/assigned\/[^/]+\/approve$/) && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const assignedChoreId = path.split('/')[4];

      // Atomic transition: only flip the row to `approved` if it's not
      // already approved. RETURNING gives us the values we need to award
      // points without a separate SELECT race window. Two parallel approve
      // requests can no longer both award.
      const transition = await pool.query(
        `UPDATE assigned_chores
            SET status = 'approved', approved_at = NOW()
          WHERE assigned_chore_id = $1 AND status <> 'approved'
        RETURNING user_id, transferred_from, transfer_type, original_points, chore_id`,
        [assignedChoreId]
      );

      if (transition.rows.length === 0) {
        // Either the chore doesn't exist or it's already approved.
        const exists = await pool.query('SELECT 1 FROM assigned_chores WHERE assigned_chore_id = $1', [assignedChoreId]);
        if (exists.rows.length === 0) return response(404, { error: 'Chore not found' });
        return response(200, { message: 'Already approved', pointsAwarded: 0 });
      }

      const row = transition.rows[0];

      // Use original_points if it was snapshotted on transfer, otherwise
      // fall back to the master chore's current points.
      let pointsValue = row.original_points;
      if (pointsValue == null) {
        const pts = await pool.query('SELECT points FROM chores WHERE chore_id = $1', [row.chore_id]);
        pointsValue = pts.rows[0]?.points ?? 0;
      }

      if (row.transfer_type === 'support' && row.transferred_from) {
        const halfPoints = Math.ceil(pointsValue / 2);
        await pool.query('UPDATE users SET points = COALESCE(points,0) + $1 WHERE user_id = $2', [halfPoints, row.user_id]);
        await pool.query('UPDATE users SET points = COALESCE(points,0) + $1 WHERE user_id = $2', [halfPoints, row.transferred_from]);
        return response(200, { message: 'Approved (support)', pointsAwarded: halfPoints, splitWith: row.transferred_from });
      } else {
        await pool.query('UPDATE users SET points = COALESCE(points,0) + $1 WHERE user_id = $2', [pointsValue, row.user_id]);
        return response(200, { message: 'Approved', pointsAwarded: pointsValue });
      }
    }

    // Transfer a chore to another family member (full points go to them)
    if (path.match(/^\/v1\/chores\/assigned\/[^/]+\/transfer$/) && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const assignedChoreId = path.split('/')[4];
      const { to_user_id } = data;
      if (!to_user_id) return response(400, { error: 'to_user_id is required' });

      // Check the chore belongs to the requesting user and is pending
      const choreResult = await pool.query(
        `SELECT ac.*, c.points FROM assigned_chores ac JOIN chores c ON ac.chore_id = c.chore_id WHERE ac.assigned_chore_id = $1`,
        [assignedChoreId]
      );
      if (choreResult.rows.length === 0) return response(404, { error: 'Chore not found' });
      const chore = choreResult.rows[0];
      if (chore.user_id !== user.userId) return response(403, { error: 'Not your chore' });
      if (chore.status !== 'pending' && chore.status !== 'in_progress') return response(400, { error: 'Can only transfer pending or in-progress chores' });

      // Reassign to the other user
      await pool.query(
        `UPDATE assigned_chores SET user_id = $1, transferred_from = $2, transfer_type = 'transfer', original_points = $3 WHERE assigned_chore_id = $4`,
        [to_user_id, user.userId, chore.points, assignedChoreId]
      );

      return response(200, { message: 'Chore transferred' });
    }

    // Request support on a chore (points split 50/50)
    if (path.match(/^\/v1\/chores\/assigned\/[^/]+\/support$/) && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const assignedChoreId = path.split('/')[4];
      const { helper_user_id } = data;
      if (!helper_user_id) return response(400, { error: 'helper_user_id is required' });

      // Check the chore belongs to the requesting user
      const choreResult = await pool.query(
        `SELECT ac.*, c.points, c.chore_id as cid FROM assigned_chores ac JOIN chores c ON ac.chore_id = c.chore_id WHERE ac.assigned_chore_id = $1`,
        [assignedChoreId]
      );
      if (choreResult.rows.length === 0) return response(404, { error: 'Chore not found' });
      const chore = choreResult.rows[0];
      if (chore.user_id !== user.userId) return response(403, { error: 'Not your chore' });
      if (chore.status !== 'pending' && chore.status !== 'in_progress') return response(400, { error: 'Can only request support on pending or in-progress chores' });

      // Mark original as support-shared
      await pool.query(
        `UPDATE assigned_chores SET transfer_type = 'support', transferred_from = $1 WHERE assigned_chore_id = $2`,
        [helper_user_id, assignedChoreId]
      );

      return response(200, { message: 'Support requested! Points will be split when completed and approved.' });
    }

    if (path.match(/^\/v1\/families\/[^/]+\/approvals$/) && httpMethod === 'GET') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const familyId = path.split('/')[3];
      const result = await pool.query(
        `SELECT ac.*, c.chore_name, c.points, u.first_name
         FROM assigned_chores ac
         JOIN chores c ON ac.chore_id = c.chore_id
         JOIN users u ON ac.user_id = u.user_id
         WHERE c.family_id = $1 AND ac.status = 'completed'
         ORDER BY ac.completed_at DESC`,
        [familyId]
      );

      return response(200, result.rows.map(r => ({
        assignedChoreId: r.assigned_chore_id,
        choreId: r.chore_id,
        userId: r.user_id,
        dueDate: dateOnly(r.due_date),
        status: r.status,
        choreName: r.chore_name,
        points: r.points,
        firstName: r.first_name,
        completedAt: isoOrNull(r.completed_at)
      })));
    }

    // Get badges for family members (weekly superstar / monthly hero)
    if (path.match(/^\/v1\/families\/[^/]+\/badges$/) && httpMethod === 'GET') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const familyId = path.split('/')[3];

      // Get all children in the family
      const childrenResult = await pool.query(
        `SELECT u.user_id, u.first_name FROM users u
         JOIN family_members fm ON u.user_id = fm.user_id
         WHERE fm.family_id = $1 AND u.role = 'child'`,
        [familyId]
      );

      const badges: Array<{ userId: string; firstName: string; weeklySuperstar: boolean; monthlyHero: boolean }> = [];

      const now = new Date();

      // Week boundaries (Mon-Sun)
      const dayOfWeek = now.getDay();
      const mondayOffset = dayOfWeek === 0 ? -6 : 1 - dayOfWeek;
      const weekStart = new Date(now);
      weekStart.setDate(now.getDate() + mondayOffset);
      weekStart.setHours(0, 0, 0, 0);
      const weekStartStr = weekStart.toISOString().split('T')[0];
      // Only count up to yesterday (today's chores may still be in progress)
      const yesterday = new Date(now);
      yesterday.setDate(now.getDate() - 1);
      const yesterdayStr = yesterday.toISOString().split('T')[0];

      // Month boundaries
      const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
      const monthStartStr = monthStart.toISOString().split('T')[0];

      for (const child of childrenResult.rows) {
        // Weekly: check if all assigned chores from weekStart..yesterday are approved or completed
        const weekChoresResult = await pool.query(
          `SELECT COUNT(*) as total,
                  COUNT(*) FILTER (WHERE ac.status IN ('approved', 'completed')) as done
           FROM assigned_chores ac
           WHERE ac.user_id = $1 AND ac.due_date >= $2 AND ac.due_date <= $3`,
          [child.user_id, weekStartStr, yesterdayStr]
        );
        const weekRow = weekChoresResult.rows[0];
        const weeklySuperstar = parseInt(weekRow.total) > 0 && parseInt(weekRow.total) === parseInt(weekRow.done);

        // Monthly: check if all assigned chores from monthStart..yesterday are approved or completed
        const monthChoresResult = await pool.query(
          `SELECT COUNT(*) as total,
                  COUNT(*) FILTER (WHERE ac.status IN ('approved', 'completed')) as done
           FROM assigned_chores ac
           WHERE ac.user_id = $1 AND ac.due_date >= $2 AND ac.due_date <= $3`,
          [child.user_id, monthStartStr, yesterdayStr]
        );
        const monthRow = monthChoresResult.rows[0];
        const monthlyHero = parseInt(monthRow.total) > 0 && parseInt(monthRow.total) === parseInt(monthRow.done);

        badges.push({
          userId: child.user_id,
          firstName: child.first_name,
          weeklySuperstar,
          monthlyHero,
        });
      }

      return response(200, badges);
    }

    // Get all assigned chores for a family (parent view)
    if (path.match(/^\/v1\/families\/[^/]+\/chores$/) && httpMethod === 'GET') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const familyId = path.split('/')[3];
      const result = await pool.query(
        `SELECT ac.*, c.chore_name, c.description, c.points, c.difficulty, c.chore_type, c.time_of_day, c.min_age, c.auto_approve, u.first_name
         FROM assigned_chores ac
         JOIN chores c ON ac.chore_id = c.chore_id
         JOIN users u ON ac.user_id = u.user_id
         WHERE c.family_id = $1
         ORDER BY ac.due_date ASC, u.first_name ASC`,
        [familyId]
      );

      return response(200, result.rows.map(r => ({
        assignedChoreId: r.assigned_chore_id,
        choreId: r.chore_id,
        userId: r.user_id,
        dueDate: dateOnly(r.due_date),
        status: r.status,
        choreName: r.chore_name,
        description: r.description,
        points: r.points,
        difficulty: r.difficulty,
        firstName: r.first_name,
        completedAt: isoOrNull(r.completed_at),
        choreType: r.chore_type || 'household',
        timeOfDay: r.time_of_day || 'anytime',
        autoApprove: !!r.auto_approve
      })));
    }

    if (path === '/v1/chores' && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const { family_id, chore_name, description, frequency, difficulty, points } = data;
      const choreId = uuidv4();

      await pool.query(
        `INSERT INTO chores (chore_id, family_id, chore_name, description, frequency, difficulty, points)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [choreId, family_id, chore_name, description, frequency || 'weekly', difficulty || 'medium', points || 15]
      );

      return response(201, { chore_id: choreId, chore_name });
    }

    // Gamification routes
    if (path.match(/^\/v1\/users\/[^/]+\/points$/) && httpMethod === 'GET') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const userId = path.split('/')[3];
      const result = await pool.query(
        'SELECT user_id, COALESCE(points, 0) as points FROM users WHERE user_id = $1',
        [userId]
      );

      if (result.rows.length === 0) return response(404, { error: 'User not found' });
      return response(200, { userId: result.rows[0].user_id, points: result.rows[0].points });
    }

    if (path.match(/^\/v1\/families\/[^/]+\/rewards$/) && httpMethod === 'GET') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const familyId = path.split('/')[3];
      const result = await pool.query(
        `SELECT r.*, u.first_name as child_name
         FROM rewards r
         LEFT JOIN users u ON r.child_id = u.user_id
         WHERE r.family_id = $1 AND r.is_active = true
         ORDER BY r.reward_type ASC, r.point_cost ASC`,
        [familyId]
      );

      return response(200, result.rows.map(r => ({
        rewardId: r.reward_id,
        familyId: r.family_id,
        rewardName: r.reward_name,
        description: r.description,
        pointCost: r.point_cost,
        rewardType: r.reward_type || 'daily',
        childId: r.child_id || null,
        childName: r.child_name || null,
        isActive: r.is_active
      })));
    }

    // Update a reward
    if (path.match(/^\/v1\/rewards\/[^/]+$/) && httpMethod === 'PATCH') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const rewardId = path.split('/')[3];
      const { reward_name, description, point_cost, reward_type, child_id } = data;

      // child_id can be explicitly set to null (all children) or a UUID
      const hasChildId = 'child_id' in data;

      let query: string;
      let params: any[];

      if (hasChildId) {
        query = `UPDATE rewards SET
          reward_name = COALESCE($1, reward_name),
          description = COALESCE($2, description),
          point_cost = COALESCE($3, point_cost),
          reward_type = COALESCE($4, reward_type),
          child_id = $5
         WHERE reward_id = $6 RETURNING *`;
        params = [reward_name, description, point_cost, reward_type, child_id || null, rewardId];
      } else {
        query = `UPDATE rewards SET
          reward_name = COALESCE($1, reward_name),
          description = COALESCE($2, description),
          point_cost = COALESCE($3, point_cost),
          reward_type = COALESCE($4, reward_type)
         WHERE reward_id = $5 RETURNING *`;
        params = [reward_name, description, point_cost, reward_type, rewardId];
      }

      const result = await pool.query(query, params);
      if (result.rows.length === 0) return response(404, { error: 'Reward not found' });
      return response(200, { message: 'Reward updated' });
    }

    // Delete (deactivate) a reward
    if (path.match(/^\/v1\/rewards\/[^/]+$/) && httpMethod === 'DELETE') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const rewardId = path.split('/')[3];
      await pool.query('UPDATE rewards SET is_active = false WHERE reward_id = $1', [rewardId]);
      return response(200, { message: 'Reward deleted' });
    }

    if (path === '/v1/rewards' && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const { family_id, reward_name, description, point_cost, reward_type, child_id } = data;
      const rewardId = uuidv4();

      await pool.query(
        `INSERT INTO rewards (reward_id, family_id, reward_name, description, point_cost, reward_type, child_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [rewardId, family_id, reward_name, description, point_cost, reward_type || 'daily', child_id || null]
      );

      return response(201, { reward_id: rewardId, reward_name, reward_type: reward_type || 'daily', child_id: child_id || null });
    }

    // Bulk create rewards (used during onboarding)
    if (path === '/v1/rewards/bulk' && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const { family_id, rewards: rewardsList } = data;
      if (!family_id || !Array.isArray(rewardsList)) {
        return response(400, { error: 'family_id and rewards array required' });
      }

      const created: string[] = [];
      for (const r of rewardsList) {
        const rewardId = uuidv4();
        await pool.query(
          `INSERT INTO rewards (reward_id, family_id, reward_name, description, point_cost, reward_type)
           VALUES ($1, $2, $3, $4, $5, $6)`,
          [rewardId, family_id, r.reward_name, r.description || '', r.point_cost, r.reward_type || 'daily']
        );
        created.push(r.reward_name);
      }

      return response(201, { message: 'Rewards created', count: created.length, rewards: created });
    }

    if (path === '/v1/rewards/redeem' && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const { user_id, reward_id } = data;

      const rewardResult = await pool.query(
        'SELECT * FROM rewards WHERE reward_id = $1 AND is_active = true',
        [reward_id]
      );

      if (rewardResult.rows.length === 0) return response(404, { error: 'Reward not found' });
      const reward = rewardResult.rows[0];

      // Atomic compare-and-swap: deduct points only if the user still has
      // enough at the moment of the UPDATE. Without this guard, two parallel
      // redemption requests could each pass the SELECT/check and leave the
      // user with negative points.
      const updated = await pool.query(
        `UPDATE users
            SET points = COALESCE(points, 0) - $1
          WHERE user_id = $2 AND COALESCE(points, 0) >= $1
        RETURNING points`,
        [reward.point_cost, user_id]
      );

      if (updated.rows.length === 0) {
        // Either user not found or insufficient points — distinguish for nicer UX.
        const exists = await pool.query('SELECT 1 FROM users WHERE user_id = $1', [user_id]);
        if (exists.rows.length === 0) return response(404, { error: 'User not found' });
        return response(400, { error: 'Insufficient points' });
      }

      return response(200, { message: 'Reward redeemed!', new_point_balance: updated.rows[0].points });
    }

    if (path.match(/^\/v1\/families\/[^/]+\/leaderboard$/) && httpMethod === 'GET') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const familyId = path.split('/')[3];
      const result = await pool.query(
        `SELECT u.user_id, u.first_name, fm.nickname, COALESCE(u.points, 0) as points,
                COALESCE(u.avatar_customizations, ARRAY[]::TEXT[]) AS avatar_customizations
           FROM users u
           JOIN family_members fm ON u.user_id = fm.user_id
          WHERE fm.family_id = $1 AND u.role = 'child'
          ORDER BY u.points DESC`,
        [familyId]
      );

      return response(200, result.rows.map((row, index) => ({
        rank: index + 1,
        userId: row.user_id,
        name: row.nickname || row.first_name,
        points: row.points,
        avatarCustomizations: row.avatar_customizations
      })));
    }

    // AI Voice Onboarding
    if (path === '/v1/ai/voice-setup' && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const { session_id, text_input, conversation_history: clientHistory } = data;

      // If no session_id, start new conversation
      if (!session_id || !text_input) {
        const newSessionId = uuidv4();
        const greeting = getInitialGreeting();
        conversationSessions.set(newSessionId, [
          { role: 'assistant', content: greeting.message }
        ]);
        return response(200, {
          session_id: newSessionId,
          ...greeting
        });
      }

      // Get conversation history — prefer server-side, fall back to client-sent history
      let history = conversationSessions.get(session_id) || [];
      if (history.length === 0 && Array.isArray(clientHistory) && clientHistory.length > 0) {
        // Lambda instance was recycled — restore from client
        history = clientHistory.map((m: any) => ({ role: m.role, content: m.content }));
        conversationSessions.set(session_id, history);
      }

      try {
        const aiResponse = await voiceOnboarding(text_input, history as any);

        // Update conversation history
        history.push({ role: 'user', content: text_input });
        history.push({ role: 'assistant', content: aiResponse.message });
        conversationSessions.set(session_id, history);

        // If complete, clean up session after a delay
        if (aiResponse.is_complete) {
          setTimeout(() => conversationSessions.delete(session_id), 60000);
        }

        return response(200, {
          session_id,
          ...aiResponse
        });
      } catch (error: any) {
        console.error('OpenAI error:', error);
        return response(500, { error: 'AI service error', details: error.message });
      }
    }

    // AI Text-to-Speech
    if (path === '/v1/ai/tts' && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const { text } = data;
      if (!text || typeof text !== 'string' || text.length === 0) {
        return response(400, { error: 'Text is required' });
      }
      if (text.length > 500) {
        return response(400, { error: 'Text must be 500 characters or fewer' });
      }

      try {
        const audioBuffer = await textToSpeechAudio(text);
        const audio_base64 = audioBuffer.toString('base64');
        return response(200, { audio_base64, content_type: 'audio/mpeg' });
      } catch (error: any) {
        console.error('TTS error:', error.message);
        return response(500, { error: 'Text-to-speech failed', details: error.message });
      }
    }

    // AI routes - Distribute chores
    if (path.match(/^\/v1\/ai\/families\/[^/]+\/distribute-chores$/) && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const familyId = path.split('/')[4];

      // Get children
      const childrenResult = await pool.query(
        `SELECT u.user_id, u.first_name, u.age FROM users u
         JOIN family_members fm ON u.user_id = fm.user_id
         WHERE fm.family_id = $1 AND u.role = 'child'`,
        [familyId]
      );

      // Get or create default chores for family
      let choresResult = await pool.query(
        'SELECT * FROM chores WHERE family_id = $1',
        [familyId]
      );

      if (choresResult.rows.length === 0) {
        // Create default chores
        const defaultChores = [
          { name: 'Make bed', difficulty: 'easy', points: 10 },
          { name: 'Set the table', difficulty: 'easy', points: 10 },
          { name: 'Clear the table', difficulty: 'easy', points: 10 },
          { name: 'Put away toys', difficulty: 'easy', points: 10 },
          { name: 'Load dishwasher', difficulty: 'medium', points: 15 },
          { name: 'Vacuum room', difficulty: 'medium', points: 20 },
          { name: 'Take out trash', difficulty: 'medium', points: 15 },
          { name: 'Fold laundry', difficulty: 'medium', points: 15 }
        ];

        for (const chore of defaultChores) {
          await pool.query(
            `INSERT INTO chores (chore_id, family_id, chore_name, frequency, difficulty, points)
             VALUES ($1, $2, $3, 'daily', $4, $5)`,
            [uuidv4(), familyId, chore.name, chore.difficulty, chore.points]
          );
        }

        choresResult = await pool.query('SELECT * FROM chores WHERE family_id = $1', [familyId]);
      }

      // Auto-create pet care and bin chores from family config
      const configResult = await pool.query('SELECT house_details FROM families WHERE family_id = $1', [familyId]);
      const houseDetails = configResult.rows[0]?.house_details || {};
      const existingChoreNames = new Set(choresResult.rows.map((c: any) => c.chore_name.toLowerCase()));

      const autoChores: Array<{ name: string; difficulty: string; points: number; frequency: string }> = [];

      // Bin chores
      if (houseDetails.bin_schedule?.collection_days?.length > 0) {
        if (!existingChoreNames.has('take bins out')) {
          autoChores.push({ name: 'Take bins out', difficulty: 'easy', points: 10, frequency: 'weekly' });
        }
        if (!existingChoreNames.has('bring bins in')) {
          autoChores.push({ name: 'Bring bins in', difficulty: 'easy', points: 10, frequency: 'weekly' });
        }
      }

      // Pet chores
      if (houseDetails.pets?.length > 0) {
        for (const pet of houseDetails.pets) {
          if (pet.type === 'dog') {
            const walkName = `Walk ${pet.name}`;
            if (!existingChoreNames.has(walkName.toLowerCase())) {
              autoChores.push({ name: walkName, difficulty: 'medium', points: 20, frequency: 'daily' });
            }
            const feedName = `Feed ${pet.name}`;
            if (!existingChoreNames.has(feedName.toLowerCase())) {
              autoChores.push({ name: feedName, difficulty: 'easy', points: 10, frequency: 'daily' });
            }
          }
          if (pet.type === 'cat') {
            const litterName = `Clean ${pet.name}'s litter`;
            if (!existingChoreNames.has(litterName.toLowerCase())) {
              autoChores.push({ name: litterName, difficulty: 'medium', points: 15, frequency: 'daily' });
            }
            const feedName = `Feed ${pet.name}`;
            if (!existingChoreNames.has(feedName.toLowerCase())) {
              autoChores.push({ name: feedName, difficulty: 'easy', points: 10, frequency: 'daily' });
            }
          }
        }
      }

      // Insert auto-generated chores
      for (const ac of autoChores) {
        await pool.query(
          `INSERT INTO chores (chore_id, family_id, chore_name, frequency, difficulty, points)
           VALUES ($1, $2, $3, $4, $5, $6)`,
          [uuidv4(), familyId, ac.name, ac.frequency, ac.difficulty, ac.points]
        );
      }

      // Refresh chores list if we added any
      if (autoChores.length > 0) {
        choresResult = await pool.query('SELECT * FROM chores WHERE family_id = $1', [familyId]);
      }

      // Also include parents if they opted in
      const parentResult = await pool.query(
        `SELECT u.user_id, u.first_name, u.age FROM users u
         JOIN family_members fm ON u.user_id = fm.user_id
         WHERE fm.family_id = $1 AND u.role = 'parent' AND u.participate_in_chores = true`,
        [familyId]
      );

      const allMembers = [
        ...childrenResult.rows.map((c: any) => ({ id: c.user_id, name: c.first_name, age: c.age, role: 'child' })),
        ...parentResult.rows.map((p: any) => ({ id: p.user_id, name: p.first_name, age: p.age, role: 'parent' })),
      ];
      if (allMembers.length === 0) {
        return response(200, { message: 'No members to distribute', assignmentsCreated: 0 });
      }

      // ── STEP 0: Auto-create daily habits if family has them configured ──
      const habitConfig = await pool.query(
        `SELECT dht.* FROM daily_habit_templates dht
         LEFT JOIN family_daily_habits fdh ON dht.template_id = fdh.template_id AND fdh.family_id = $1
         WHERE fdh.is_active IS NULL OR fdh.is_active = true`,
        [familyId]
      );

      // Create daily habit chores if not already in the chores table (idempotent)
      for (const habit of habitConfig.rows) {
        // Consistent naming: "Brush teeth (AM)" or "Brush teeth (PM)" for duplicated habits, otherwise just the name
        const suffix = habit.template_id.endsWith('_am') ? ' (AM)' : habit.template_id.endsWith('_pm') ? ' (PM)' : '';
        const habitChoreName = habit.habit_name + suffix;

        const existsResult = await pool.query(
          `SELECT 1 FROM chores WHERE family_id = $1 AND chore_name = $2 AND chore_type = 'daily_habit'`,
          [familyId, habitChoreName]
        );
        if (existsResult.rows.length === 0) {
          await pool.query(
            `INSERT INTO chores (chore_id, family_id, chore_name, description, frequency, difficulty, points, chore_type, time_of_day, min_age)
             VALUES ($1, $2, $3, $4, 'daily_habit', 'easy', $5, 'daily_habit', $6, $7)`,
            [uuidv4(), familyId, habitChoreName, habit.description || '', habit.points || 1, habit.time_of_day, habit.min_age || 3]
          );
        }
      }

      // ── STEP 0b: Create pet/routine chores from family config ──
      const familyConfigResult = await pool.query('SELECT house_details FROM families WHERE family_id = $1', [familyId]);
      const familyHouseDetails = familyConfigResult.rows[0]?.house_details || {};

      // Pet chores (routine type, daily, tied to rotation)
      if (familyHouseDetails.pets && Array.isArray(familyHouseDetails.pets)) {
        for (const pet of familyHouseDetails.pets) {
          if (pet.type === 'dog' || pet.walk_rotation_children?.length > 0) {
            const walkName = `Walk ${pet.name}`;
            const exists = await pool.query('SELECT 1 FROM chores WHERE family_id = $1 AND chore_name = $2', [familyId, walkName]);
            if (exists.rows.length === 0) {
              await pool.query(
                `INSERT INTO chores (chore_id, family_id, chore_name, description, frequency, difficulty, points, chore_type, time_of_day, min_age)
                 VALUES ($1, $2, $3, $4, 'daily', 'medium', 10, 'routine', 'anytime', 6)`,
                [uuidv4(), familyId, walkName, `Take ${pet.name} for a walk`]
              );
            }
          }
          const feedName = `Feed ${pet.name}`;
          const feedExists = await pool.query('SELECT 1 FROM chores WHERE family_id = $1 AND chore_name = $2', [familyId, feedName]);
          if (feedExists.rows.length === 0) {
            await pool.query(
              `INSERT INTO chores (chore_id, family_id, chore_name, description, frequency, difficulty, points, chore_type, time_of_day, min_age)
               VALUES ($1, $2, $3, $4, 'daily', 'easy', 5, 'routine', 'morning', 5)`,
              [uuidv4(), familyId, feedName, `Give ${pet.name} breakfast and water`]
            );
          }
          if (pet.type === 'cat' || pet.litter_rotation_children?.length > 0) {
            const litterName = `Clean ${pet.name}'s litter`;
            const litterExists = await pool.query('SELECT 1 FROM chores WHERE family_id = $1 AND chore_name = $2', [familyId, litterName]);
            if (litterExists.rows.length === 0) {
              await pool.query(
                `INSERT INTO chores (chore_id, family_id, chore_name, description, frequency, difficulty, points, chore_type, time_of_day, min_age)
                 VALUES ($1, $2, $3, $4, 'daily', 'medium', 10, 'routine', 'evening', 8)`,
                [uuidv4(), familyId, litterName, `Clean and refresh ${pet.name}'s litter tray`]
              );
            }
          }
          // Weekly feeder refill — top up the auto-feeder hopper. Distinct from
          // the daily "feed" task (bowl top-up). Uses 'household' type so the
          // AI distributor handles weekly rotation rather than the pet-rotation
          // path which expects daily cadence.
          const refillName = `Refill ${pet.name}'s feeder`;
          const refillExists = await pool.query('SELECT 1 FROM chores WHERE family_id = $1 AND chore_name = $2', [familyId, refillName]);
          if (refillExists.rows.length === 0) {
            await pool.query(
              `INSERT INTO chores (chore_id, family_id, chore_name, description, frequency, difficulty, points, chore_type, time_of_day, min_age)
               VALUES ($1, $2, $3, $4, 'weekly', 'easy', 15, 'household', 'anytime', 6)`,
              [uuidv4(), familyId, refillName, `Top up ${pet.name}'s auto-feeder hopper for the week`]
            );
          }
        }
      }

      // Refresh chores after adding habits + pet chores
      choresResult = await pool.query('SELECT * FROM chores WHERE family_id = $1 AND is_active = true', [familyId]);

      // Separate chores by type
      const dailyHabits = choresResult.rows.filter((c: any) => c.chore_type === 'daily_habit');
      const routineChores = choresResult.rows.filter((c: any) => c.chore_type === 'routine');
      const householdChores = choresResult.rows.filter((c: any) => !c.chore_type || c.chore_type === 'household' || c.chore_type === 'laundry' || c.chore_type === 'personal_space');

      if (householdChores.length === 0 && dailyHabits.length === 0 && routineChores.length === 0) {
        return response(200, { message: 'No chores to distribute', assignmentsCreated: 0 });
      }

      const chores = householdChores; // AI distributes household chores only (routine handled by rotation above)

      // Build 7 days starting today
      const today = new Date();
      const days: string[] = [];
      for (let i = 0; i < 7; i++) {
        const d = new Date(today);
        d.setDate(today.getDate() + i);
        days.push(d.toISOString().split('T')[0]);
      }

      // ── STEP 0.5: Clear existing pending daily habit assignments before re-creating ──
      await pool.query(
        `DELETE FROM assigned_chores
         WHERE user_id IN (SELECT user_id FROM family_members WHERE family_id = $1)
           AND due_date >= $2
           AND status = 'pending'
           AND chore_id IN (SELECT chore_id FROM chores WHERE family_id = $1 AND chore_type = 'daily_habit')`,
        [familyId, days[0]]
      );

      // ── STEP 0.6: Assign daily habits to ALL eligible children for 7 days ──
      let habitsCreated = 0;
      for (const habit of dailyHabits) {
        const habitMinAge = habit.min_age || 3;
        for (const day of days) {
          for (const member of allMembers) {
            if (member.age && member.age < habitMinAge) continue;
            try {
              await pool.query(
                `INSERT INTO assigned_chores (assigned_chore_id, chore_id, user_id, due_date, status)
                 VALUES ($1, $2, $3, $4, 'pending')
                 ON CONFLICT (chore_id, user_id, due_date) DO NOTHING`,
                [uuidv4(), habit.chore_id, member.id, day]
              );
              habitsCreated++;
            } catch {}
          }
        }
      }

      // ── STEP 0.7: Clear + assign routine chores (pets) using rotation from config ──
      await pool.query(
        `DELETE FROM assigned_chores
         WHERE user_id IN (SELECT user_id FROM family_members WHERE family_id = $1)
           AND due_date >= $2
           AND status = 'pending'
           AND chore_id IN (SELECT chore_id FROM chores WHERE family_id = $1 AND chore_type = 'routine')`,
        [familyId, days[0]]
      );
      // Fallback rotation = every child in the family. Used when the parent
      // hasn't configured a per-task rotation (so the chore still gets done
      // instead of silently going unassigned, which is the bug Hossam hit
      // with Fifi's litter on 2026-05-08).
      const allChildIds = childrenResult.rows.map((c: any) => c.user_id);

      for (const routine of routineChores) {
        const choreName = routine.chore_name;
        // Find matching pet rotation
        let rotationChildren: string[] = [];
        if (familyHouseDetails.pets) {
          for (const pet of familyHouseDetails.pets) {
            if (choreName.includes(pet.name)) {
              if (choreName.toLowerCase().includes('walk')) {
                rotationChildren = pet.walk_rotation_children || [];
              } else if (choreName.toLowerCase().includes('litter')) {
                rotationChildren = pet.litter_rotation_children || [];
              } else if (choreName.toLowerCase().includes('feed') || choreName.toLowerCase().includes('refill')) {
                // Feeding (daily) and feeder refill (weekly) — anyone in any rotation
                rotationChildren = (pet.walk_rotation_children || []).concat(pet.litter_rotation_children || []);
                // Dedupe
                rotationChildren = Array.from(new Set(rotationChildren));
              }
            }
          }
        }
        // Fall back to all children if config is empty.
        if (rotationChildren.length === 0) rotationChildren = allChildIds;

        if (rotationChildren.length > 0) {
          // Assign with daily rotation among the rotation children
          for (let dayIdx = 0; dayIdx < 7; dayIdx++) {
            const assignedChild = rotationChildren[dayIdx % rotationChildren.length];
            try {
              await pool.query(
                `INSERT INTO assigned_chores (assigned_chore_id, chore_id, user_id, due_date, status)
                 VALUES ($1, $2, $3, $4, 'pending')
                 ON CONFLICT (chore_id, user_id, due_date) DO NOTHING`,
                [uuidv4(), routine.chore_id, assignedChild, days[dayIdx]]
              );
              habitsCreated++;
            } catch {}
          }
        }
      }

      // ── STEP 1: Delete old pending future assignments for household chores only (not habits/routine) ──
      await pool.query(
        `DELETE FROM assigned_chores
         WHERE user_id IN (SELECT user_id FROM family_members WHERE family_id = $1)
           AND due_date >= $2
           AND status = 'pending'
           AND chore_id IN (SELECT chore_id FROM chores WHERE family_id = $1 AND (chore_type IS NULL OR chore_type = 'household' OR chore_type = 'laundry' OR chore_type = 'personal_space'))`,
        [familyId, days[0]]
      );

      // ── STEP 2: Try AI distribution ──
      const choreInput = chores.map((c: any) => ({ name: c.chore_name, difficulty: c.difficulty, points: c.points }));
      const memberInput = allMembers.map(m => ({ name: m.name, age: m.age, role: m.role }));

      let aiSchedule: Array<Array<{ chore: number; member: number }>> | null = null;
      try {
        const result = await aiDistributeChores({ members: memberInput, chores: choreInput, numDays: 7 });
        if (result && result.length > 0) aiSchedule = result;
      } catch (err: any) {
        console.error('AI distribution failed:', err.message);
      }

      let assignmentsCreated = 0;

      // ── STEP 3: Build validated schedule ──
      // Whether from AI or fallback, we enforce rules before inserting
      const finalSchedule: Array<{ date: string; choreIdx: number; memberIdx: number }> = [];

      if (aiSchedule && aiSchedule.length >= 7) {
        // Map AI output, validate indices, and enforce no-duplicate-per-day
        for (let dayIdx = 0; dayIdx < 7; dayIdx++) {
          const dayAssignments = aiSchedule[dayIdx] || [];
          const usedChoresThisDay = new Set<number>();

          for (const a of dayAssignments) {
            if (typeof a.chore !== 'number' || typeof a.member !== 'number') continue;
            if (a.chore < 0 || a.chore >= chores.length) continue;
            if (a.member < 0 || a.member >= allMembers.length) continue;
            // No same chore twice in one day
            if (usedChoresThisDay.has(a.chore)) continue;
            usedChoresThisDay.add(a.chore);
            finalSchedule.push({ date: days[dayIdx], choreIdx: a.chore, memberIdx: a.member });
          }
        }
      }

      // If AI gave us too few assignments, use deterministic fallback
      const expectedMin = allMembers.length * 2 * 7;
      if (finalSchedule.length < expectedMin * 0.5) {
        console.log(`AI schedule too sparse (${finalSchedule.length}/${expectedMin}), using fallback`);
        finalSchedule.length = 0; // clear

        // Deterministic round-robin: rotate chores across members and days
        for (let dayIdx = 0; dayIdx < 7; dayIdx++) {
          const usedChoresThisDay = new Set<number>();

          for (let memberIdx = 0; memberIdx < allMembers.length; memberIdx++) {
            const member = allMembers[memberIdx];
            let assigned = 0;

            // Start at a different offset each day to rotate
            const startOffset = (dayIdx * 2 + memberIdx * 3) % chores.length;

            for (let k = 0; k < chores.length && assigned < 2; k++) {
              const choreIdx = (startOffset + k) % chores.length;
              const chore = chores[choreIdx];

              // Skip if already used today
              if (usedChoresThisDay.has(choreIdx)) continue;
              // Age filter
              if (chore.difficulty === 'hard' && member.age && member.age < 8) continue;
              if (chore.difficulty === 'medium' && member.age && member.age < 4) continue;

              usedChoresThisDay.add(choreIdx);
              finalSchedule.push({ date: days[dayIdx], choreIdx, memberIdx });
              assigned++;
            }
          }
        }
      }

      // ── STEP 3.5: Fairness post-processing ──
      // Rebalance the schedule so every family member ends up with within
      // 1 chore of every other (and roughly balanced points), regardless of
      // whether the AI or fallback produced the schedule. Without this the
      // AI can drift to "everyone gets 2/day" locally while leaving global
      // counts uneven once age filters drop assignments.
      const countByMember = new Array<number>(allMembers.length).fill(0);
      const pointsByMember = new Array<number>(allMembers.length).fill(0);
      for (const e of finalSchedule) {
        countByMember[e.memberIdx]++;
        pointsByMember[e.memberIdx] += chores[e.choreIdx].points || 10;
      }

      const ageOk = (member: any, chore: any) => {
        if (chore.difficulty === 'hard' && member.age && member.age < 8) return false;
        if (chore.difficulty === 'medium' && member.age && member.age < 4) return false;
        return true;
      };

      // Move chores from busiest → least-loaded member until gap ≤ 1.
      // Cap iterations to prevent any pathological loop.
      for (let iter = 0; iter < 100; iter++) {
        let maxIdx = 0, minIdx = 0;
        for (let i = 1; i < allMembers.length; i++) {
          if (countByMember[i] > countByMember[maxIdx]) maxIdx = i;
          if (countByMember[i] < countByMember[minIdx]) minIdx = i;
        }
        if (countByMember[maxIdx] - countByMember[minIdx] <= 1) break;

        const minMember = allMembers[minIdx];
        const minHasOnDay = new Set(
          finalSchedule
            .filter(e => e.memberIdx === minIdx)
            .map(e => `${e.date}:${e.choreIdx}`)
        );

        let moved = false;
        for (const entry of finalSchedule) {
          if (entry.memberIdx !== maxIdx) continue;
          const chore = chores[entry.choreIdx];
          if (!ageOk(minMember, chore)) continue;
          if (minHasOnDay.has(`${entry.date}:${entry.choreIdx}`)) continue;
          entry.memberIdx = minIdx;
          countByMember[maxIdx]--;
          countByMember[minIdx]++;
          pointsByMember[maxIdx] -= chore.points || 10;
          pointsByMember[minIdx] += chore.points || 10;
          moved = true;
          break;
        }
        if (!moved) break; // can't rebalance (age constraints)
      }

      console.log(
        `Fairness: chores per member = [${countByMember.join(', ')}], ` +
        `points per member = [${pointsByMember.join(', ')}]`
      );

      // ── STEP 4: Insert into DB ──
      for (const entry of finalSchedule) {
        const choreId = chores[entry.choreIdx].chore_id;
        const userId = allMembers[entry.memberIdx].id;
        try {
          await pool.query(
            `INSERT INTO assigned_chores (assigned_chore_id, chore_id, user_id, due_date, status)
             VALUES ($1, $2, $3, $4, 'pending')
             ON CONFLICT (chore_id, user_id, due_date) DO NOTHING`,
            [uuidv4(), choreId, userId, entry.date]
          );
          assignmentsCreated++;
        } catch (e: any) {
          // Skip duplicates silently
        }
      }

      return response(200, { message: 'Chores distributed', assignmentsCreated });
    }

    // AI Room Analysis with GPT-4 Vision
    if (path === '/v1/ai/analyze-room' && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const { image } = data;
      if (!image) {
        return response(400, { error: 'Image is required' });
      }

      console.log('Analyzing room image, data length:', image?.length || 0);

      try {
        const result = await analyzeRoomImage(image);
        console.log('Room analysis result:', JSON.stringify(result));
        return response(200, result);
      } catch (error: any) {
        console.error('Room analysis error:', error.message, error.stack);
        return response(500, { error: 'Failed to analyze room', details: error.message });
      }
    }

    // Add rooms and generate chores
    if (path.match(/^\/v1\/families\/[^/]+\/rooms$/) && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const familyId = path.split('/')[3];
      const { rooms } = data;

      // Append new rooms to existing scanned_rooms (don't overwrite other config)
      const currentResult = await pool.query('SELECT house_details FROM families WHERE family_id = $1', [familyId]);
      const details = currentResult.rows[0]?.house_details || {};
      const existingRooms: any[] = details.scanned_rooms || [];

      // Merge: if same room name exists, combine assets (dedup). Otherwise add new.
      const mergedRooms = [...existingRooms];
      for (const newRoom of rooms) {
        const roomName = (newRoom.name || '').toLowerCase();
        const existingIdx = mergedRooms.findIndex((r: any) => r.name.toLowerCase() === roomName);
        if (existingIdx >= 0) {
          // Merge assets (combine + deduplicate)
          const existingAssets = new Set((mergedRooms[existingIdx].assets || []).map((a: string) => a.toLowerCase()));
          const newAssets = (newRoom.assets || []).filter((a: string) => !existingAssets.has(a.toLowerCase()));
          mergedRooms[existingIdx].assets = [...(mergedRooms[existingIdx].assets || []), ...newAssets];
          // Keep higher confidence
          if ((newRoom.confidence || 0) > (mergedRooms[existingIdx].confidence || 0)) {
            mergedRooms[existingIdx].confidence = newRoom.confidence;
          }
        } else {
          mergedRooms.push({ name: newRoom.name, confidence: newRoom.confidence, assets: newRoom.assets || [] });
        }
      }

      details.scanned_rooms = mergedRooms;
      await pool.query('UPDATE families SET house_details = $1 WHERE family_id = $2', [JSON.stringify(details), familyId]);

      const choresCreated: string[] = [];
      for (const room of rooms) {
        for (const choreName of room.suggestedChores) {
          const choreId = uuidv4();
          // Smarter difficulty inference based on chore keywords
          let difficulty = 'easy';
          const lower = choreName.toLowerCase();
          if (lower.includes('deep clean') || lower.includes('scrub') || lower.includes('mop') || lower.includes('organiz')) {
            difficulty = 'hard';
          } else if (lower.includes('clean') || lower.includes('vacuum') || lower.includes('wash') || lower.includes('sweep')) {
            difficulty = 'medium';
          }
          const points = difficulty === 'hard' ? 25 : difficulty === 'medium' ? 15 : 10;

          await pool.query(
            `INSERT INTO chores (chore_id, family_id, chore_name, description, frequency, difficulty, points, room_type)
             VALUES ($1, $2, $3, $4, 'weekly', $5, $6, $7)
             ON CONFLICT DO NOTHING`,
            [choreId, familyId, choreName, `${choreName} in the ${room.name}`, difficulty, points, room.name]
          );
          choresCreated.push(choreName);
        }
      }

      return response(201, { message: 'Rooms and chores added', choresCreated, roomsScanned: roomDetails.length });
    }

    // ─── JOBS BOARD ───

    // Create a job (parent)
    if (path === '/v1/jobs' && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const { family_id, title, description, reward_type, reward_amount, job_type, due_date, pitch_reason, proposed_price } = data;
      if (!family_id || !title || !reward_amount) {
        return response(400, { error: 'family_id, title, and reward_amount are required' });
      }

      // Check if this is a child proposing a contract
      const userResult = await pool.query('SELECT role FROM users WHERE user_id = $1', [user.userId]);
      const isChild = userResult.rows[0]?.role === 'child';
      const status = isChild ? 'proposed' : 'open';

      const jobId = uuidv4();
      await pool.query(
        `INSERT INTO jobs (job_id, family_id, posted_by, title, description, reward_type, reward_amount, job_type, due_date, status, pitch_reason, proposed_price)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)`,
        [jobId, family_id, user.userId, title, description || '', reward_type || 'points',
         isChild ? (proposed_price || reward_amount) : reward_amount,
         job_type || 'open', due_date || null, status, pitch_reason || null, proposed_price || null]
      );

      return response(201, {
        job_id: jobId, title,
        status,
        message: isChild ? 'Contract pitched! Waiting for parent approval.' : undefined
      });
    }

    // List jobs for a family
    if (path.match(/^\/v1\/families\/[^/]+\/jobs$/) && httpMethod === 'GET') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const familyId = path.split('/')[3];

      // Auto-expire overdue open/assigned jobs and deduct points
      const overdueResult = await pool.query(
        `UPDATE jobs SET status = 'expired'
         WHERE family_id = $1 AND status IN ('assigned') AND due_date < CURRENT_DATE
         RETURNING job_id, assigned_to, reward_amount`,
        [familyId]
      );
      // Deduct credibility points for overdue assigned jobs
      for (const expired of overdueResult.rows) {
        if (expired.assigned_to) {
          const penalty = Math.ceil(Number(expired.reward_amount) * 0.2);
          await pool.query(
            'UPDATE users SET points = GREATEST(COALESCE(points,0) - $1, 0) WHERE user_id = $2',
            [penalty, expired.assigned_to]
          );
        }
      }

      const result = await pool.query(
        `SELECT j.*, u.first_name as posted_by_name, a.first_name as assigned_to_name,
                (SELECT COUNT(*) FROM job_applications ja WHERE ja.job_id = j.job_id AND ja.status = 'pending') as application_count
         FROM jobs j
         JOIN users u ON j.posted_by = u.user_id
         LEFT JOIN users a ON j.assigned_to = a.user_id
         WHERE j.family_id = $1
         ORDER BY
           CASE j.status WHEN 'proposed' THEN 0 WHEN 'open' THEN 1 WHEN 'assigned' THEN 2 WHEN 'completed' THEN 3 WHEN 'confirmed' THEN 4 ELSE 5 END,
           j.created_at DESC`,
        [familyId]
      );

      return response(200, result.rows.map(r => ({
        jobId: r.job_id,
        familyId: r.family_id,
        postedBy: r.posted_by,
        postedByName: r.posted_by_name,
        title: r.title,
        description: r.description,
        rewardType: r.reward_type,
        rewardAmount: Number(r.reward_amount),
        jobType: r.job_type,
        dueDate: dateOnly(r.due_date),
        status: r.status,
        assignedTo: r.assigned_to,
        assignedToName: r.assigned_to_name,
        applicationCount: parseInt(r.application_count),
        createdAt: isoOrNull(r.created_at),
        pitchReason: r.pitch_reason || null,
        proposedPrice: r.proposed_price ? Number(r.proposed_price) : null,
      })));
    }

    // Apply to / accept a job (child)
    if (path.match(/^\/v1\/jobs\/[^/]+\/apply$/) && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const jobId = path.split('/')[3];
      const { reason, bid_amount } = data;

      // Get job details
      const jobResult = await pool.query('SELECT * FROM jobs WHERE job_id = $1', [jobId]);
      if (jobResult.rows.length === 0) return response(404, { error: 'Job not found' });
      const job = jobResult.rows[0];

      if (job.status !== 'open') {
        return response(400, { error: 'This job is no longer open' });
      }

      // Check if already applied
      const existingApp = await pool.query(
        'SELECT 1 FROM job_applications WHERE job_id = $1 AND user_id = $2',
        [jobId, user.userId]
      );
      if (existingApp.rows.length > 0) {
        return response(400, { error: 'You have already applied to this job' });
      }

      if (job.job_type === 'open') {
        // First come first served — assign immediately
        await pool.query(
          `UPDATE jobs SET status = 'assigned', assigned_to = $1, assigned_at = NOW() WHERE job_id = $2`,
          [user.userId, jobId]
        );
        // Create application record too
        const appId = uuidv4();
        await pool.query(
          `INSERT INTO job_applications (application_id, job_id, user_id, reason, status)
           VALUES ($1, $2, $3, $4, 'accepted')`,
          [appId, jobId, user.userId, reason || 'Accepted (open job)']
        );
        return response(200, { message: 'Job accepted! It\'s yours.', assigned: true });
      } else {
        // Application-based — submit application
        const appId = uuidv4();
        await pool.query(
          `INSERT INTO job_applications (application_id, job_id, user_id, reason, bid_amount)
           VALUES ($1, $2, $3, $4, $5)`,
          [appId, jobId, user.userId, reason || '', bid_amount || null]
        );
        return response(201, { message: 'Application submitted!', application_id: appId });
      }
    }

    // Get applications for a job (parent)
    if (path.match(/^\/v1\/jobs\/[^/]+\/applications$/) && httpMethod === 'GET') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const jobId = path.split('/')[3];
      const result = await pool.query(
        `SELECT ja.*, u.first_name, u.age
         FROM job_applications ja
         JOIN users u ON ja.user_id = u.user_id
         WHERE ja.job_id = $1
         ORDER BY ja.created_at ASC`,
        [jobId]
      );

      return response(200, result.rows.map(r => ({
        applicationId: r.application_id,
        jobId: r.job_id,
        userId: r.user_id,
        firstName: r.first_name,
        age: r.age,
        reason: r.reason,
        bidAmount: r.bid_amount ? Number(r.bid_amount) : null,
        status: r.status,
        createdAt: isoOrNull(r.created_at),
        counterAmount: r.counter_amount ? Number(r.counter_amount) : null,
        counterMessage: r.counter_message || null,
        negotiationRound: r.negotiation_round || 0,
      })));
    }

    // Assign job to applicant (parent picks winner)
    if (path.match(/^\/v1\/jobs\/[^/]+\/assign$/) && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const jobId = path.split('/')[3];
      const { application_id } = data;

      // Get application
      const appResult = await pool.query(
        'SELECT * FROM job_applications WHERE application_id = $1 AND job_id = $2',
        [application_id, jobId]
      );
      if (appResult.rows.length === 0) return response(404, { error: 'Application not found' });

      const app = appResult.rows[0];

      // Update job
      await pool.query(
        `UPDATE jobs SET status = 'assigned', assigned_to = $1, assigned_at = NOW() WHERE job_id = $2`,
        [app.user_id, jobId]
      );

      // Accept this application, reject others
      await pool.query(
        `UPDATE job_applications SET status = 'accepted' WHERE application_id = $1`,
        [application_id]
      );
      await pool.query(
        `UPDATE job_applications SET status = 'rejected' WHERE job_id = $1 AND application_id != $2`,
        [jobId, application_id]
      );

      return response(200, { message: 'Job assigned!' });
    }

    // Mark job as completed (child)
    if (path.match(/^\/v1\/jobs\/[^/]+\/complete$/) && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const jobId = path.split('/')[3];

      const jobResult = await pool.query('SELECT * FROM jobs WHERE job_id = $1', [jobId]);
      if (jobResult.rows.length === 0) return response(404, { error: 'Job not found' });

      if (jobResult.rows[0].assigned_to !== user.userId) {
        return response(403, { error: 'This job is not assigned to you' });
      }

      await pool.query(
        `UPDATE jobs SET status = 'completed', completed_at = NOW() WHERE job_id = $1`,
        [jobId]
      );

      return response(200, { message: 'Job marked as completed. Waiting for parent confirmation.' });
    }

    // Confirm job completion (parent) — awards points or marks cash for payout
    if (path.match(/^\/v1\/jobs\/[^/]+\/confirm$/) && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const jobId = path.split('/')[3];

      const jobResult = await pool.query('SELECT * FROM jobs WHERE job_id = $1', [jobId]);
      if (jobResult.rows.length === 0) return response(404, { error: 'Job not found' });
      const job = jobResult.rows[0];

      if (job.status !== 'completed') {
        return response(400, { error: 'Job has not been marked as completed yet' });
      }

      // Award reward
      if (job.reward_type === 'points') {
        await pool.query(
          'UPDATE users SET points = COALESCE(points,0) + $1 WHERE user_id = $2',
          [Number(job.reward_amount), job.assigned_to]
        );
      }

      await pool.query(
        `UPDATE jobs SET status = 'confirmed', confirmed_at = NOW() WHERE job_id = $1`,
        [jobId]
      );

      return response(200, {
        message: job.reward_type === 'points'
          ? `Confirmed! ${job.reward_amount} points awarded.`
          : `Confirmed! Please give the child ${job.reward_amount} cash.`,
        rewardType: job.reward_type,
        rewardAmount: Number(job.reward_amount),
      });
    }

    // Approve kid-proposed contract (parent)
    if (path.match(/^\/v1\/jobs\/[^/]+\/approve-proposal$/) && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });
      const jobId = path.split('/')[3];
      const jobResult = await pool.query('SELECT * FROM jobs WHERE job_id = $1', [jobId]);
      if (jobResult.rows.length === 0) return response(404, { error: 'Contract not found' });
      const job = jobResult.rows[0];
      if (job.status !== 'proposed') return response(400, { error: 'This contract is not a proposal' });
      const { adjusted_amount } = data;
      const finalAmount = adjusted_amount || job.reward_amount;
      await pool.query(`UPDATE jobs SET status = 'open', reward_amount = $1 WHERE job_id = $2`, [finalAmount, jobId]);
      return response(200, { message: 'Proposal approved! Contract is now open.', job_id: jobId });
    }

    // Reject kid-proposed contract (parent)
    if (path.match(/^\/v1\/jobs\/[^/]+\/reject-proposal$/) && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });
      const jobId = path.split('/')[3];
      await pool.query(`UPDATE jobs SET status = 'rejected' WHERE job_id = $1 AND status = 'proposed'`, [jobId]);
      return response(200, { message: 'Proposal rejected.' });
    }

    // Counter-offer on job application (parent → child)
    if (path.match(/^\/v1\/jobs\/[^/]+\/applications\/[^/]+\/counter$/) && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });
      const parts = path.split('/');
      const jobId = parts[3];
      const appId = parts[5];
      const { amount, message: counterMsg } = data;
      await pool.query(
        `UPDATE job_applications SET counter_amount = $1, counter_message = $2, negotiation_round = COALESCE(negotiation_round, 0) + 1 WHERE application_id = $3 AND job_id = $4`,
        [amount, counterMsg || null, appId, jobId]
      );
      return response(200, { message: 'Counter-offer sent!', amount });
    }

    // Accept counter-offer (child)
    if (path.match(/^\/v1\/jobs\/[^/]+\/applications\/[^/]+\/accept-counter$/) && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });
      const parts = path.split('/');
      const jobId = parts[3];
      const appId = parts[5];
      // Get the counter amount and use it as the new bid
      const appResult = await pool.query('SELECT counter_amount FROM job_applications WHERE application_id = $1', [appId]);
      if (appResult.rows.length === 0) return response(404, { error: 'Application not found' });
      const counterAmount = appResult.rows[0].counter_amount;
      await pool.query(
        `UPDATE job_applications SET bid_amount = $1, status = 'accepted' WHERE application_id = $2`,
        [counterAmount, appId]
      );
      // Assign the job to this applicant
      await pool.query(
        `UPDATE jobs SET status = 'assigned', assigned_to = $1, reward_amount = $2 WHERE job_id = $3`,
        [user.userId, counterAmount, jobId]
      );
      return response(200, { message: 'Counter-offer accepted! Contract assigned.' });
    }

    // Create subcontract (assigned child hires sibling)
    if (path.match(/^\/v1\/jobs\/[^/]+\/subcontract$/) && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });
      const jobId = path.split('/')[3];
      const { subcontractor_id, amount, task_description } = data;
      if (!subcontractor_id || !amount) return response(400, { error: 'subcontractor_id and amount required' });

      // Verify user is assigned to this job
      const jobResult = await pool.query('SELECT * FROM jobs WHERE job_id = $1 AND assigned_to = $2', [jobId, user.userId]);
      if (jobResult.rows.length === 0) return response(403, { error: 'You are not assigned to this contract' });
      if (Number(amount) >= Number(jobResult.rows[0].reward_amount)) return response(400, { error: 'Subcontract amount must be less than contract reward' });

      const subId = uuidv4();
      await pool.query(
        `INSERT INTO job_applications (application_id, job_id, user_id, reason, bid_amount, status)
         VALUES ($1, $2, $3, $4, $5, 'subcontract_offered')`,
        [subId, jobId, subcontractor_id, task_description || 'Subcontract work', amount]
      );
      return response(201, { subcontract_id: subId, message: 'Subcontract offer sent!' });
    }

    // Accept subcontract (sibling)
    if (path.match(/^\/v1\/jobs\/[^/]+\/subcontract\/[^/]+\/accept$/) && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });
      const parts = path.split('/');
      const subId = parts[5];
      await pool.query(
        `UPDATE job_applications SET status = 'subcontract_accepted' WHERE application_id = $1 AND user_id = $2`,
        [subId, user.userId]
      );
      return response(200, { message: 'Subcontract accepted!' });
    }

    // Complete subcontract (sibling marks done)
    if (path.match(/^\/v1\/jobs\/[^/]+\/subcontract\/[^/]+\/complete$/) && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });
      const parts = path.split('/');
      const subId = parts[5];
      await pool.query(
        `UPDATE job_applications SET status = 'subcontract_completed' WHERE application_id = $1 AND user_id = $2`,
        [subId, user.userId]
      );
      return response(200, { message: 'Subcontract work marked as done!' });
    }

    // Get subcontracts for a job
    if (path.match(/^\/v1\/jobs\/[^/]+\/subcontracts$/) && httpMethod === 'GET') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });
      const jobId = path.split('/')[3];
      const result = await pool.query(
        `SELECT ja.application_id as subcontract_id, ja.job_id, ja.user_id as subcontractor_id,
                u.first_name as subcontractor_name, ja.reason as task_description,
                ja.bid_amount as amount, ja.status
         FROM job_applications ja
         JOIN users u ON ja.user_id = u.user_id
         WHERE ja.job_id = $1 AND ja.status LIKE 'subcontract_%'`,
        [jobId]
      );
      return response(200, result.rows.map((r: any) => ({
        subcontractId: r.subcontract_id, parentJobId: r.job_id,
        subcontractorId: r.subcontractor_id, subcontractorName: r.subcontractor_name,
        taskDescription: r.task_description, amount: Number(r.amount), status: r.status
      })));
    }

    // Contract stats / portfolio (child)
    if (path.match(/^\/v1\/users\/[^/]+\/contract-stats$/) && httpMethod === 'GET') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });
      const userId = path.split('/')[3];
      // Get all confirmed contracts for this user
      const confirmed = await pool.query(
        `SELECT reward_amount, due_date, confirmed_at, posted_by FROM jobs WHERE assigned_to = $1 AND status = 'confirmed'`,
        [userId]
      );
      const proposed = await pool.query(
        `SELECT status FROM jobs WHERE posted_by = $1 AND pitch_reason IS NOT NULL`,
        [userId]
      );
      const totalContracts = confirmed.rows.length;
      const totalEarnings = confirmed.rows.reduce((sum: number, r: any) => sum + Number(r.reward_amount), 0);
      const onTime = confirmed.rows.filter((r: any) => !r.due_date || new Date(r.confirmed_at) <= new Date(r.due_date)).length;
      const onTimePercentage = totalContracts > 0 ? Math.round((onTime / totalContracts) * 100) : 100;
      const proposalsTotal = proposed.rows.length;
      const proposalsAccepted = proposed.rows.filter((r: any) => r.status !== 'rejected' && r.status !== 'proposed').length;

      return response(200, {
        totalContracts, totalEarnings, onTimePercentage,
        proposalsTotal, proposalsAccepted,
        proposalSuccessRate: proposalsTotal > 0 ? Math.round((proposalsAccepted / proposalsTotal) * 100) : 0
      });
    }

    // Get daily habit templates
    if (path === '/v1/daily-habits/templates' && httpMethod === 'GET') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });
      const result = await pool.query('SELECT * FROM daily_habit_templates ORDER BY time_of_day, sort_order');
      return response(200, result.rows.map((r: any) => ({
        templateId: r.template_id, habitName: r.habit_name, timeOfDay: r.time_of_day,
        minAge: r.min_age, points: r.points, description: r.description
      })));
    }

    // Configure family daily habits
    if (path.match(/^\/v1\/families\/[^/]+\/daily-habits$/) && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });
      const familyId = path.split('/')[3];
      const { habits } = data; // [{template_id, is_active}]
      if (!Array.isArray(habits)) return response(400, { error: 'habits array required' });
      for (const h of habits) {
        await pool.query(
          `INSERT INTO family_daily_habits (family_id, template_id, is_active) VALUES ($1, $2, $3)
           ON CONFLICT (family_id, template_id) DO UPDATE SET is_active = $3`,
          [familyId, h.template_id, h.is_active !== false]
        );
      }
      return response(200, { message: 'Daily habits updated' });
    }

    // Get family daily habits config
    if (path.match(/^\/v1\/families\/[^/]+\/daily-habits$/) && httpMethod === 'GET') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });
      const familyId = path.split('/')[3];
      const result = await pool.query(
        `SELECT dht.*, COALESCE(fdh.is_active, true) as is_active
         FROM daily_habit_templates dht
         LEFT JOIN family_daily_habits fdh ON dht.template_id = fdh.template_id AND fdh.family_id = $1
         ORDER BY dht.time_of_day, dht.sort_order`,
        [familyId]
      );
      return response(200, result.rows.map((r: any) => ({
        templateId: r.template_id, habitName: r.habit_name, timeOfDay: r.time_of_day,
        minAge: r.min_age, points: r.points, description: r.description, isActive: r.is_active
      })));
    }

    // Remove family member (parent removes child or other parent)
    if (path.match(/^\/v1\/families\/[^/]+\/members\/[^/]+$/) && httpMethod === 'DELETE') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });
      const familyId = path.split('/')[3];
      const memberId = path.split('/')[5];

      // Can't remove yourself
      if (memberId === user.userId) return response(400, { error: "You can't remove yourself" });

      // Verify requester is a parent in this family
      const parentCheck = await pool.query(
        "SELECT 1 FROM users WHERE user_id = $1 AND family_id = $2 AND role = 'parent'",
        [user.userId, familyId]
      );
      if (parentCheck.rows.length === 0) return response(403, { error: 'Only parents can remove members' });

      // Get member name before removing
      const memberResult = await pool.query('SELECT first_name, role FROM users WHERE user_id = $1', [memberId]);
      const memberName = memberResult.rows[0]?.first_name || 'Member';

      // Delete assigned chores for this member
      await pool.query('DELETE FROM assigned_chores WHERE user_id = $1', [memberId]);
      // Delete job applications
      await pool.query('DELETE FROM job_applications WHERE user_id = $1', [memberId]);
      // Delete from family_members
      await pool.query('DELETE FROM family_members WHERE family_id = $1 AND user_id = $2', [familyId, memberId]);
      // Remove family_id from user (they can rejoin later)
      await pool.query('UPDATE users SET family_id = NULL WHERE user_id = $1', [memberId]);
      // Delete invitations for this user
      await pool.query('DELETE FROM child_invitations WHERE child_user_id = $1', [memberId]);

      return response(200, { message: `${memberName} has been removed from the family` });
    }

    // Delete entire family (nuclear option — removes all data)
    if (path.match(/^\/v1\/families\/[^/]+$/) && httpMethod === 'DELETE') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });
      const familyId = path.split('/')[3];

      // Verify requester is a parent in this family
      const parentCheck = await pool.query(
        "SELECT 1 FROM users WHERE user_id = $1 AND family_id = $2 AND role = 'parent'",
        [user.userId, familyId]
      );
      if (parentCheck.rows.length === 0) return response(403, { error: 'Only parents can delete the family' });

      // Get all member IDs
      const members = await pool.query('SELECT user_id FROM family_members WHERE family_id = $1', [familyId]);
      const memberIds = members.rows.map((m: any) => m.user_id);

      if (memberIds.length > 0) {
        // Delete all chore-related data
        await pool.query('DELETE FROM assigned_chores WHERE user_id = ANY($1)', [memberIds]);
        await pool.query('DELETE FROM job_applications WHERE user_id = ANY($1)', [memberIds]);
        await pool.query('DELETE FROM user_rewards WHERE user_id = ANY($1)', [memberIds]);
        await pool.query('DELETE FROM points_history WHERE user_id = ANY($1)', [memberIds]);
        await pool.query('DELETE FROM screen_time_settings WHERE user_id = ANY($1)', [memberIds]);
      }

      // Delete family-level data
      await pool.query('DELETE FROM jobs WHERE family_id = $1', [familyId]);
      await pool.query('DELETE FROM chores WHERE family_id = $1', [familyId]);
      await pool.query('DELETE FROM rewards WHERE family_id = $1', [familyId]);
      await pool.query('DELETE FROM child_invitations WHERE family_id = $1', [familyId]);
      await pool.query('DELETE FROM family_daily_habits WHERE family_id = $1', [familyId]);
      await pool.query('DELETE FROM family_members WHERE family_id = $1', [familyId]);

      // Remove family_id from all users and delete users without email (non-account children)
      await pool.query('UPDATE users SET family_id = NULL WHERE family_id = $1', [familyId]);
      await pool.query('DELETE FROM users WHERE family_id IS NULL AND email IS NULL');

      // Delete the family itself
      await pool.query('DELETE FROM families WHERE family_id = $1', [familyId]);

      return response(200, { message: 'Family and all associated data have been permanently deleted' });
    }

    // Update family name/house type
    if (path.match(/^\/v1\/families\/[^/]+$/) && httpMethod === 'PATCH') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });
      const familyId = path.split('/')[3];
      const { family_name, house_type } = data;
      const updates: string[] = [];
      const params: any[] = [];
      let idx = 1;
      if (family_name) { updates.push(`family_name = $${idx++}`); params.push(family_name); }
      if (house_type) { updates.push(`house_type = $${idx++}`); params.push(house_type); }
      if (updates.length === 0) return response(400, { error: 'Nothing to update' });
      params.push(familyId);
      await pool.query(`UPDATE families SET ${updates.join(', ')} WHERE family_id = $${idx}`, params);
      return response(200, { message: 'Family updated' });
    }

    // Update user details (parent can edit child's name/age)
    if (path.match(/^\/v1\/users\/[^/]+$/) && httpMethod === 'PATCH') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });
      const userId = path.split('/')[3];
      const { first_name, age, emoji } = data;
      const updates: string[] = [];
      const params: any[] = [];
      let idx = 1;
      if (first_name) { updates.push(`first_name = $${idx++}`); params.push(first_name); }
      if (age) { updates.push(`age = $${idx++}`); params.push(Number(age)); }
      if (emoji) { updates.push(`emoji = $${idx++}`); params.push(emoji); }
      if (data.role && (data.role === 'parent' || data.role === 'child')) {
        updates.push(`role = $${idx++}`); params.push(data.role);
        // Also update family_members table
      }
      if (updates.length === 0) return response(400, { error: 'Nothing to update' });
      params.push(userId);
      await pool.query(`UPDATE users SET ${updates.join(', ')} WHERE user_id = $${idx}`, params);
      // Sync role in family_members if changed
      if (data.role) {
        await pool.query('UPDATE family_members SET role = $1 WHERE user_id = $2', [data.role, userId]);
      }
      return response(200, { message: 'Updated', user_id: userId });
    }

    // Parent participation toggle
    if (path.match(/^\/v1\/users\/[^/]+\/participate$/) && httpMethod === 'PATCH') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const userId = path.split('/')[3];
      const { participate } = data;

      await pool.query(
        'UPDATE users SET participate_in_chores = $1 WHERE user_id = $2',
        [!!participate, userId]
      );

      return response(200, { message: 'Updated', participate_in_chores: !!participate });
    }

    if (path.match(/^\/v1\/users\/[^/]+\/participate$/) && httpMethod === 'GET') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const userId = path.split('/')[3];
      const result = await pool.query(
        'SELECT COALESCE(participate_in_chores, false) as participate FROM users WHERE user_id = $1',
        [userId]
      );

      return response(200, { participate_in_chores: result.rows[0]?.participate || false });
    }

    // Screen Time Management
    if (path.match(/^\/v1\/users\/[^/]+\/screen-time$/) && httpMethod === 'GET') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const userId = path.split('/')[3];
      const result = await pool.query(
        'SELECT * FROM screen_time_settings WHERE user_id = $1',
        [userId]
      );

      if (result.rows.length === 0) {
        return response(200, {
          userId,
          dailyLimitMinutes: 120,
          mustCompleteDailyChores: true,
          minimumPointsRequired: 0,
          isActive: true
        });
      }

      const settings = result.rows[0];
      return response(200, {
        userId: settings.user_id,
        dailyLimitMinutes: settings.daily_limit_minutes,
        mustCompleteDailyChores: settings.must_complete_daily_chores,
        minimumPointsRequired: settings.minimum_points_required,
        isActive: settings.is_active
      });
    }

    if (path.match(/^\/v1\/users\/[^/]+\/screen-time$/) && httpMethod === 'PUT') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const userId = path.split('/')[3];
      const { daily_limit_minutes, must_complete_daily_chores, minimum_points_required } = data;

      await pool.query(
        `INSERT INTO screen_time_settings (setting_id, user_id, daily_limit_minutes, must_complete_daily_chores, minimum_points_required)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (user_id) DO UPDATE SET
           daily_limit_minutes = $3,
           must_complete_daily_chores = $4,
           minimum_points_required = $5,
           updated_at = NOW()`,
        [uuidv4(), userId, daily_limit_minutes, must_complete_daily_chores, minimum_points_required]
      );

      return response(200, { message: 'Screen time settings updated' });
    }

    if (path.match(/^\/v1\/users\/[^/]+\/screen-time\/access$/) && httpMethod === 'GET') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const userId = path.split('/')[3];

      // Get screen time settings
      const settingsResult = await pool.query(
        'SELECT * FROM screen_time_settings WHERE user_id = $1',
        [userId]
      );

      const settings = settingsResult.rows[0] || {
        daily_limit_minutes: 120,
        must_complete_daily_chores: true,
        minimum_points_required: 0
      };

      // Get user's points
      const pointsResult = await pool.query(
        'SELECT COALESCE(points, 0) as points FROM users WHERE user_id = $1',
        [userId]
      );
      const currentPoints = pointsResult.rows[0]?.points || 0;

      // Check daily chores completion
      const today = new Date().toISOString().split('T')[0];
      const choresResult = await pool.query(
        `SELECT COUNT(*) as total,
                SUM(CASE WHEN status IN ('completed', 'approved') THEN 1 ELSE 0 END) as done
         FROM assigned_chores
         WHERE user_id = $1 AND due_date = $2`,
        [userId, today]
      );

      const totalChores = parseInt(choresResult.rows[0]?.total) || 0;
      const completedChores = parseInt(choresResult.rows[0]?.done) || 0;
      const allChoresDone = totalChores === 0 || completedChores >= totalChores;

      // Determine access
      const hasEnoughPoints = currentPoints >= settings.minimum_points_required;
      const choreRequirementMet = !settings.must_complete_daily_chores || allChoresDone;
      const hasAccess = hasEnoughPoints && choreRequirementMet;

      return response(200, {
        hasAccess,
        dailyLimitMinutes: settings.daily_limit_minutes,
        currentPoints,
        minimumPointsRequired: settings.minimum_points_required,
        hasEnoughPoints,
        choreRequirementMet,
        totalChores,
        completedChores,
        reason: !hasAccess
          ? (!hasEnoughPoints ? 'Need more points' : 'Complete your daily chores first')
          : null
      });
    }

    // Child Invitation System
    // Create invitation for a child
    if (path.match(/^\/v1\/children\/[^/]+\/invite$/) && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const childUserId = path.split('/')[3];

      // Verify child exists and belongs to the same family
      const childResult = await pool.query(
        `SELECT u.user_id, u.first_name, u.family_id, u.email
         FROM users u WHERE u.user_id = $1 AND u.role = 'child'`,
        [childUserId]
      );

      if (childResult.rows.length === 0) {
        return response(404, { error: 'Child not found' });
      }

      const child = childResult.rows[0];

      // Check if child already has login credentials
      if (child.email) {
        return response(400, { error: 'Child already has login credentials' });
      }

      // Generate a secure random token
      const crypto = await import('crypto');
      const invitationToken = crypto.randomBytes(32).toString('hex');

      // Set expiration to 7 days from now
      const expiresAt = new Date();
      expiresAt.setDate(expiresAt.getDate() + 7);

      // Invalidate any existing active invitations for this child
      await pool.query(
        `UPDATE child_invitations SET expires_at = NOW()
         WHERE child_user_id = $1 AND claimed_at IS NULL AND expires_at > NOW()`,
        [childUserId]
      );

      // Generate short 6-char invite code
      const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no I/O/0/1 to avoid confusion
      let inviteCode = '';
      const cryptoMod = await import('crypto');
      const bytes = cryptoMod.randomBytes(6);
      for (let i = 0; i < 6; i++) inviteCode += chars[bytes[i] % chars.length];

      // Create new invitation with short code
      await pool.query(
        `INSERT INTO child_invitations (family_id, child_user_id, invitation_token, invite_code, expires_at, created_by)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [child.family_id, childUserId, invitationToken, inviteCode, expiresAt, user.userId]
      );

      return response(201, {
        invitation_token: invitationToken,
        invite_code: inviteCode,
        expires_at: expiresAt.toISOString(),
        child_name: child.first_name
      });
    }

    // Validate invitation (public - no auth required)
    if (path.match(/^\/v1\/invitations\/[^/]+$/) && httpMethod === 'GET') {
      const token = path.split('/')[3];

      const result = await pool.query(
        `SELECT ci.invitation_id, ci.family_id, ci.child_user_id, ci.expires_at, ci.claimed_at,
                u.first_name as child_name, f.family_name
         FROM child_invitations ci
         JOIN users u ON ci.child_user_id = u.user_id
         JOIN families f ON ci.family_id = f.family_id
         WHERE ci.invitation_token = $1`,
        [token]
      );

      if (result.rows.length === 0) {
        return response(404, { error: 'Invitation not found' });
      }

      const invitation = result.rows[0];

      if (invitation.claimed_at) {
        return response(400, { error: 'Invitation has already been claimed' });
      }

      if (new Date(invitation.expires_at) < new Date()) {
        return response(400, { error: 'Invitation has expired' });
      }

      return response(200, {
        valid: true,
        child_name: invitation.child_name,
        family_name: invitation.family_name
      });
    }

    // Claim invitation (public - no auth required)
    if (path.match(/^\/v1\/invitations\/[^/]+\/claim$/) && httpMethod === 'POST') {
      const token = path.split('/')[3];
      const { email, password } = data;

      if (!email || !password) {
        return response(400, { error: 'Email and password are required' });
      }

      // Validate email format
      const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
      if (!emailRegex.test(email)) {
        return response(400, { error: 'Invalid email format' });
      }

      // Check password length
      if (password.length < 6) {
        return response(400, { error: 'Password must be at least 6 characters' });
      }

      // Check if email is already in use
      const existingUser = await pool.query(
        'SELECT user_id FROM users WHERE email = $1',
        [email]
      );

      if (existingUser.rows.length > 0) {
        return response(409, { error: 'Email already in use' });
      }

      // Get invitation
      const invResult = await pool.query(
        `SELECT ci.invitation_id, ci.family_id, ci.child_user_id, ci.expires_at, ci.claimed_at
         FROM child_invitations ci
         WHERE ci.invitation_token = $1`,
        [token]
      );

      if (invResult.rows.length === 0) {
        return response(404, { error: 'Invitation not found' });
      }

      const invitation = invResult.rows[0];

      if (invitation.claimed_at) {
        return response(400, { error: 'Invitation has already been claimed' });
      }

      if (new Date(invitation.expires_at) < new Date()) {
        return response(400, { error: 'Invitation has expired' });
      }

      // Hash password
      const passwordHash = await bcrypt.hash(password, 10);

      // Update child's user record with email and password
      await pool.query(
        `UPDATE users SET email = $1, password_hash = $2 WHERE user_id = $3`,
        [email, passwordHash, invitation.child_user_id]
      );

      // Mark invitation as claimed
      await pool.query(
        `UPDATE child_invitations SET claimed_at = NOW() WHERE invitation_id = $1`,
        [invitation.invitation_id]
      );

      // Generate JWT token for the child
      const jwtToken = jwt.sign(
        { userId: invitation.child_user_id, email, role: 'child' },
        JWT_SECRET,
        { expiresIn: '7d' }
      );

      return response(200, {
        message: 'Account activated successfully',
        user_id: invitation.child_user_id,
        email,
        token: jwtToken
      });
    }

    // Child generates a "link me" code (child without family wants parent to add them)
    if (path === '/v1/auth/generate-link-code' && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      // Verify user is a child without a family
      const userResult = await pool.query('SELECT user_id, first_name, family_id, role FROM users WHERE user_id = $1', [user.userId]);
      if (userResult.rows.length === 0) return response(404, { error: 'User not found' });
      const u = userResult.rows[0];
      if (u.role !== 'child') return response(400, { error: 'Only children can generate link codes' });
      if (u.family_id) return response(400, { error: 'You are already in a family' });

      // Generate 6-char code
      const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      const cryptoMod = await import('crypto');
      const bytes = cryptoMod.randomBytes(6);
      let linkCode = '';
      for (let i = 0; i < 6; i++) linkCode += chars[bytes[i] % chars.length];

      // Store in user record (reuse a simple approach — store in a temp column or use existing table)
      // We'll store it as a special invitation where the child IS the creator
      const expiresAt = new Date();
      expiresAt.setDate(expiresAt.getDate() + 7);

      // Delete any existing link codes for this child
      await pool.query(
        `DELETE FROM child_invitations WHERE child_user_id = $1 AND created_by = $1`,
        [user.userId]
      );

      await pool.query(
        `INSERT INTO child_invitations (invitation_id, family_id, child_user_id, invitation_token, invite_code, expires_at, created_by)
         VALUES ($1, NULL, $2, $3, $4, $5, $2)`,
        [uuidv4(), user.userId, cryptoMod.randomBytes(32).toString('hex'), linkCode, expiresAt]
      );

      return response(201, {
        link_code: linkCode,
        child_name: u.first_name,
        expires_at: expiresAt.toISOString()
      });
    }

    // Parent links an existing child account to their family using the child's link code
    if (path === '/v1/families/link-child' && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });

      const { link_code } = data;
      if (!link_code) return response(400, { error: 'link_code is required' });

      // Verify parent has a family
      const parentResult = await pool.query('SELECT family_id FROM users WHERE user_id = $1', [user.userId]);
      if (!parentResult.rows[0]?.family_id) return response(400, { error: 'You must have a family first' });
      const familyId = parentResult.rows[0].family_id;

      // Find the link code
      const invResult = await pool.query(
        `SELECT ci.*, u.first_name, u.age FROM child_invitations ci
         JOIN users u ON ci.child_user_id = u.user_id
         WHERE ci.invite_code = $1 AND ci.created_by = ci.child_user_id`,
        [link_code.toUpperCase()]
      );
      if (invResult.rows.length === 0) return response(404, { error: 'Invalid link code' });
      const inv = invResult.rows[0];
      if (inv.claimed_at) return response(400, { error: 'This link code has already been used' });
      if (new Date(inv.expires_at) < new Date()) return response(400, { error: 'This link code has expired' });

      // Check child doesn't already have a family
      const childCheck = await pool.query('SELECT family_id FROM users WHERE user_id = $1', [inv.child_user_id]);
      if (childCheck.rows[0]?.family_id) return response(400, { error: 'This child is already in a family' });

      // Link child to parent's family
      await pool.query('UPDATE users SET family_id = $1 WHERE user_id = $2', [familyId, inv.child_user_id]);
      await pool.query(
        'INSERT INTO family_members (family_id, user_id, role) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING',
        [familyId, inv.child_user_id, 'child']
      );

      // Mark invitation as claimed
      await pool.query('UPDATE child_invitations SET claimed_at = NOW(), family_id = $1 WHERE invitation_id = $2', [familyId, inv.invitation_id]);

      // Get family name
      const famResult = await pool.query('SELECT family_name FROM families WHERE family_id = $1', [familyId]);

      return response(200, {
        message: `${inv.first_name} has been added to your family!`,
        child_user_id: inv.child_user_id,
        child_name: inv.first_name,
        child_age: inv.age,
        family_name: famResult.rows[0]?.family_name
      });
    }

    // Generate parent/partner invite code
    if (path.match(/^\/v1\/families\/[^/]+\/invite-parent$/) && httpMethod === 'POST') {
      const user = getUserFromToken(event);
      if (!user) return response(401, { error: 'Unauthorized' });
      const familyId = path.split('/')[3];

      // Generate codes
      const crypto = await import('crypto');
      const invitationToken = crypto.randomBytes(32).toString('hex');
      const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      const bytes = crypto.randomBytes(6);
      let inviteCode = '';
      for (let i = 0; i < 6; i++) inviteCode += chars[bytes[i] % chars.length];

      const expiresAt = new Date();
      expiresAt.setDate(expiresAt.getDate() + 7);

      // Create a "parent invitation" — child_user_id is NULL, role stored in reason field
      await pool.query(
        `INSERT INTO child_invitations (invitation_id, family_id, child_user_id, invitation_token, invite_code, expires_at, created_by)
         VALUES ($1, $2, NULL, $3, $4, $5, $6)`,
        [uuidv4(), familyId, invitationToken, inviteCode, expiresAt, user.userId]
      );

      return response(201, {
        invite_code: inviteCode,
        invitation_token: invitationToken,
        expires_at: expiresAt.toISOString(),
        role: 'parent'
      });
    }

    // Validate invitation by SHORT CODE (public)
    if (path.match(/^\/v1\/invitations\/code\/[^/]+$/) && httpMethod === 'GET') {
      const code = path.split('/')[4].toUpperCase();
      const result = await pool.query(
        `SELECT ci.*, u.first_name as child_name, f.family_name
         FROM child_invitations ci
         LEFT JOIN users u ON ci.child_user_id = u.user_id
         JOIN families f ON ci.family_id = f.family_id
         WHERE ci.invite_code = $1`,
        [code]
      );
      if (result.rows.length === 0) return response(404, { error: 'Invalid invite code' });
      const inv = result.rows[0];
      if (inv.claimed_at) return response(400, { error: 'This invite code has already been used' });
      if (new Date(inv.expires_at) < new Date()) return response(400, { error: 'This invite code has expired' });
      const isParentInvite = !inv.child_user_id;
      return response(200, {
        valid: true,
        child_name: isParentInvite ? null : inv.child_name,
        family_name: inv.family_name,
        invite_code: code,
        role: isParentInvite ? 'parent' : 'child',
        expires_at: inv.expires_at
      });
    }

    // Claim invitation by SHORT CODE (public — handles both child and parent invites)
    if (path.match(/^\/v1\/invitations\/code\/[^/]+\/claim$/) && httpMethod === 'POST') {
      const code = path.split('/')[4].toUpperCase();
      const { email, password, first_name } = data;
      if (!email || !password) return response(400, { error: 'Email and password required' });
      if (password.length < 6) return response(400, { error: 'Password must be at least 6 characters' });

      // Find invitation by code (LEFT JOIN since parent invites have no child_user_id)
      const invResult = await pool.query(
        `SELECT ci.*, u.first_name FROM child_invitations ci
         LEFT JOIN users u ON ci.child_user_id = u.user_id
         WHERE ci.invite_code = $1`,
        [code]
      );
      if (invResult.rows.length === 0) return response(404, { error: 'Invalid invite code' });
      const invitation = invResult.rows[0];
      if (invitation.claimed_at) return response(400, { error: 'This invite code has already been used' });
      if (new Date(invitation.expires_at) < new Date()) return response(400, { error: 'This invite code has expired' });

      // Check email not taken
      const emailCheck = await pool.query('SELECT 1 FROM users WHERE email = $1', [email]);
      if (emailCheck.rows.length > 0) return response(409, { error: 'Email already in use' });

      const passwordHash = await bcrypt.hash(password, 10);
      let userId: string;
      let role: string;

      if (invitation.child_user_id) {
        // CHILD invitation — update existing child account
        userId = invitation.child_user_id;
        role = 'child';
        await pool.query('UPDATE users SET email = $1, password_hash = $2 WHERE user_id = $3', [email, passwordHash, userId]);
      } else {
        // PARENT invitation — create new parent account and join family
        userId = uuidv4();
        role = 'parent';
        const parentName = first_name || 'Parent';
        await pool.query(
          `INSERT INTO users (user_id, email, password_hash, first_name, role, family_id) VALUES ($1, $2, $3, $4, 'parent', $5)`,
          [userId, email, passwordHash, parentName, invitation.family_id]
        );
        await pool.query(
          'INSERT INTO family_members (family_id, user_id, role) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING',
          [invitation.family_id, userId, 'parent']
        );
      }

      // Mark invitation as claimed
      await pool.query('UPDATE child_invitations SET claimed_at = NOW() WHERE invitation_id = $1', [invitation.invitation_id]);

      const jwtToken = jwt.sign({ userId, email, role }, JWT_SECRET, { expiresIn: '7d' });

      return response(200, {
        message: role === 'parent' ? 'Welcome to the family!' : 'Account activated!',
        user_id: userId,
        email,
        token: jwtToken,
        role
      });
    }

    return response(404, { error: 'Not found', path, method: httpMethod });

  } catch (error: any) {
    console.error('Error:', error);
    return response(500, { error: 'Internal server error', details: error.message });
  }
};
