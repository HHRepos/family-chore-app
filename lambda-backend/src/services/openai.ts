import OpenAI from 'openai';

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

interface ConversationMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

interface VoiceOnboardingResponse {
  message: string;
  extracted_data: {
    family_name: string | null;
    house_type: string | null;
    children: Array<{ name: string; age: number }>;
    bin_schedule: {
      bins: Array<{ type: string; collection_day: string; frequency: string }>;
      rotation: string | null; // "children" | "family" | "specific_person" | null
      rotation_person: string | null;
    } | null;
    pets: Array<{ name: string; type: string; care_tasks: string[] }> | null;
  };
  is_complete: boolean;
  ready_for_room_scan: boolean;
}

const VOICE_ONBOARDING_SYSTEM_PROMPT = `You're a family assistant chatting with a parent who's setting up their family chore app. Be natural — like a friend helping out, not a form to fill in.

YOUR JOB: Gather family info through genuine conversation. Don't rush. React to what they say. Show personality.

WHAT YOU NEED (roughly in this order, but be flexible):
- Are they a parent? (confirm early)
- Family name
- Home type (house/apartment/condo/townhouse) — DON'T just ask "what type of home?" Instead weave it in: "And are you guys in a house, apartment...?"
- Kids — names and ages. Ask about each one. Show interest ("Nice name! How old?"). After each kid, naturally check: "Anyone else?"
- Bins — offer to set up bin schedule. If yes: what bins? (waste, recycling, garden, etc.) What days? Weekly or fortnightly? Who takes them out — kids rotate, everyone rotates, or one person?
- Pets — any pets? If yes: name, type. For dogs: walking rotation? For cats: litter duty? Who does it?
- Room scanning — offer to scan rooms with camera for chore ideas. If they say yes, set ready_for_room_scan to true and tell them "A scan button should appear below — tap it to photograph each room."

HOW TO TALK:
- 1-2 sentences max per response. Be brief.
- DON'T say "Great!", "Got it!", "Awesome!", "Perfect!" or any generic filler. Instead react specifically to what they said: "The Johnsons — love it." or "A 7-year-old, nice age for starting chores."
- DON'T rush through questions like a checklist. Let it breathe.
- If they give you multiple things at once ("I'm a parent, we're the Smiths, we live in a house, 2 kids"), acknowledge ALL of it and move forward naturally.
- Use contractions. Sound human.
- If something seems off, gently check: "Just checking — did you say age 2?"
- If they want to change something, just update it.

IMPORTANT — ROOM SCANNING:
- When you offer room scanning and they say YES, set ready_for_room_scan to true
- Do NOT set is_complete at the same time. Let them scan first.
- Only set is_complete AFTER they've either scanned rooms or said they're done scanning.
- Tell them explicitly: "Tap the Scan button below to photograph your rooms."

IMPORTANT — COMPLETION:
- Do NOT set is_complete until you've asked about bins, pets, AND offered room scanning
- Before finishing, give a quick summary: "So we've got the [Name] family — [Kid1] (age X) and [Kid2] (age Y), bins on [days], [pet name] the [type]. Everything look right?"
- Only set is_complete = true after they confirm the summary

Always respond with valid JSON:
{
  "message": "your response",
  "extracted_data": {
    "family_name": "name or null",
    "house_type": "house|apartment|condo|townhouse or null",
    "children": [{"name": "child name", "age": number}],
    "bin_schedule": {
      "bins": [{"type": "waste", "collection_day": "monday", "frequency": "weekly"}],
      "rotation": "children|family|specific_person or null",
      "rotation_person": "name or null"
    },
    "pets": [{"name": "Buddy", "type": "dog", "care_tasks": ["walk", "feed"]}]
  },
  "is_complete": false,
  "ready_for_room_scan": false
}

Rules:
- Always carry forward ALL data collected so far — never reset arrays
- bin_schedule and pets should be null until the user engages with them
- ready_for_room_scan = true ONLY when user says yes to scanning (never at same time as is_complete)
- is_complete = true ONLY after summary is confirmed by user`;

export async function voiceOnboarding(
  userMessage: string,
  conversationHistory: ConversationMessage[]
): Promise<VoiceOnboardingResponse> {
  const messages: ConversationMessage[] = [
    { role: 'system', content: VOICE_ONBOARDING_SYSTEM_PROMPT },
    ...conversationHistory,
    { role: 'user', content: userMessage }
  ];

  const completion = await openai.chat.completions.create({
    model: 'gpt-4o',
    messages: messages,
    temperature: 0.85,
    max_tokens: 250,
    response_format: { type: 'json_object' }
  });

  const responseContent = completion.choices[0]?.message?.content || '{}';

  try {
    const parsed = JSON.parse(responseContent) as VoiceOnboardingResponse;
    return {
      message: parsed.message || "Sorry, I missed that — could you say it again?",
      extracted_data: {
        family_name: parsed.extracted_data?.family_name || null,
        house_type: parsed.extracted_data?.house_type || null,
        children: parsed.extracted_data?.children || [],
        bin_schedule: parsed.extracted_data?.bin_schedule || null,
        pets: parsed.extracted_data?.pets || null
      },
      is_complete: parsed.is_complete || false,
      ready_for_room_scan: parsed.ready_for_room_scan || false
    };
  } catch {
    return {
      message: "I'm having a moment — could you tell me your family's last name?",
      extracted_data: {
        family_name: null,
        house_type: null,
        children: [],
        bin_schedule: null,
        pets: null
      },
      is_complete: false,
      ready_for_room_scan: false
    };
  }
}

export function getInitialGreeting(): VoiceOnboardingResponse {
  return {
    message: "Hey! I'll help you get your family set up — chores, routines, all of it. Quick question first: are you a parent or guardian?",
    extracted_data: {
      family_name: null,
      house_type: null,
      children: [],
      bin_schedule: null,
      pets: null
    },
    is_complete: false,
    ready_for_room_scan: false
  };
}

interface RoomAnalysisResult {
  rooms: Array<{
    name: string;
    confidence: number;
    assets: string[];
    suggestedChores: string[];
  }>;
}

export async function analyzeRoomImage(imageBase64: string): Promise<RoomAnalysisResult> {
  // Handle data URL format (e.g., "data:image/jpeg;base64,/9j/4AAQ...")
  let base64Data = imageBase64;
  let mediaType = 'image/jpeg';

  if (imageBase64.startsWith('data:')) {
    const matches = imageBase64.match(/^data:([^;]+);base64,(.+)$/);
    if (matches) {
      mediaType = matches[1];
      base64Data = matches[2];
    }
  }

  console.log('Calling GPT-4o vision, media type:', mediaType, 'base64 length:', base64Data.length);

  try {
    const completion = await openai.chat.completions.create({
      model: 'gpt-4o',
      messages: [
        {
          role: 'system',
          content: `You are a smart home room analyser for a family chore management app. Your job is to thoroughly analyse a photo of a room and identify:

1. **Room type** — Kitchen, Bedroom, Living Room, Bathroom, Dining Room, Garage, Laundry Room, Home Office, Playroom, Hallway, Pantry, Closet, Backyard/Garden, etc.
2. **Confidence score** — 0.0 to 1.0 for how sure you are about the room type
3. **Detected assets/objects** — List EVERY identifiable household item, appliance, and fixture. Be thorough and SMART about modern appliances:
   - Look for robot vacuums (Roomba, Roborock, etc.), dishwashers, tumble dryers, washing machines, smart home devices
   - Look for specific brands/models if visible
   - Standard items: refrigerator, oven, microwave, sink, toaster, coffee machine, trash can, table, chairs, couch, TV, bookshelf, bed, nightstand, dresser, toilet, shower, bathtub, washer, dryer, vacuum, mop, broom, plants, pet items, rugs, curtains, shelves, desk, computer, lamp, etc.
4. **Smart chore suggestions** — Based on the room AND the specific assets detected, suggest 4-8 specific chores with these smart rules:
   - **Robot vacuum detected**: Do NOT suggest "vacuum the floor". Instead suggest maintenance tasks: "Empty robot vacuum dustbin", "Clean robot vacuum brushes", "Check robot vacuum sensors". If it has a mop function, add "Refill robot mop water tank".
   - **Dishwasher detected**: Suggest "Load dishwasher", "Unload dishwasher", "Wipe dishwasher door" — NOT "wash dishes by hand".
   - **Tumble dryer detected**: Suggest "Clean dryer lint filter", "Transfer clothes to dryer" — NOT "hang clothes to dry".
   - **Washing machine detected**: Suggest "Load washing machine", "Transfer to dryer/drying rack", "Wipe washing machine door seal".
   - For all smart/automated appliances, focus on MAINTENANCE tasks rather than the manual equivalent.
   - Be specific: "Wipe kitchen counters" not just "Clean".

IMPORTANT:
- Only identify rooms you can actually see. If unclear, return an empty rooms array.
- Be THOROUGH with asset detection — the more items you identify, the better chore suggestions we can make.
- Filter out low-confidence detections (below 0.5).
- Chores should be practical, family-appropriate, and respect automation (don't create manual tasks that appliances handle).

Respond with valid JSON:
{
  "rooms": [
    {
      "name": "Kitchen",
      "confidence": 0.95,
      "assets": ["refrigerator", "dishwasher", "robot vacuum", "oven", "microwave", "sink", "trash can", "dining table"],
      "suggestedChores": ["Wipe kitchen counters", "Load dishwasher", "Unload dishwasher", "Empty robot vacuum dustbin", "Take out kitchen trash", "Clean microwave", "Wipe dining table"]
    }
  ]
}`
        },
        {
          role: 'user',
          content: [
            {
              type: 'image_url',
              image_url: {
                url: `data:${mediaType};base64,${base64Data}`,
                detail: 'high'
              }
            },
            {
              type: 'text',
              text: 'Analyse this room photo thoroughly. Identify the room type, list every visible household item and appliance, and suggest specific chores based on what you see.'
            }
          ]
        }
      ],
      max_tokens: 800,
      response_format: { type: 'json_object' }
    });

    const responseContent = completion.choices[0]?.message?.content || '{}';
    console.log('GPT-4o response:', responseContent);

    const parsed = JSON.parse(responseContent) as RoomAnalysisResult;

    // Filter out low-confidence rooms
    const filteredRooms = (parsed.rooms || []).filter(r => r.confidence >= 0.5);

    return {
      rooms: filteredRooms.map(r => ({
        name: r.name,
        confidence: r.confidence,
        assets: r.assets || [],
        suggestedChores: r.suggestedChores || [],
      }))
    };
  } catch (error: any) {
    console.error('GPT-4o vision error:', error.message);
    throw error;
  }
}

// AI returns indices not UUIDs — much more reliable
interface ChoreDistributionInput {
  members: Array<{ name: string; age: number | null; role: string }>;
  chores: Array<{ name: string; difficulty: string; points: number }>;
  numDays: number;
}

// AI returns: day index → array of { chore: choreIndex, member: memberIndex }
type AiSchedule = Array<Array<{ chore: number; member: number }>>;

export async function aiDistributeChores(input: ChoreDistributionInput): Promise<AiSchedule> {
  const memberList = input.members.map((m, i) => `  ${i}: ${m.name} (age: ${m.age || 'adult'}, ${m.role})`).join('\n');
  const choreList = input.chores.map((c, i) => `  ${i}: ${c.name} [${c.difficulty}, ${c.points}pts]`).join('\n');

  const completion = await openai.chat.completions.create({
    model: 'gpt-4o-mini',
    temperature: 0.3,
    messages: [
      {
        role: 'system',
        content: `You create weekly chore schedules. Output ONLY a JSON array of ${input.numDays} arrays. Each inner array contains objects with "chore" (chore index) and "member" (member index).

RULES:
- Each person gets exactly 2 chores per day
- On any given day, a chore can only be assigned to ONE person (no duplicates within a day)
- Don't give the same chore to the same person on consecutive days
- Children under 4: only easy chores. Under 8: no hard chores.
- FAIRNESS IS CRITICAL. Across the full week:
  - Every person must end up with the same total number of chores (within 1)
  - Total points per person must be balanced (within ~10% of each other)
  - Mix difficulties so no one is stuck with only hard or only easy

Output format (example with 2 members, 3 chores, 2 days):
[[{"chore":0,"member":0},{"chore":1,"member":0},{"chore":2,"member":1},{"chore":0,"member":1}],[{"chore":1,"member":1},{"chore":2,"member":0},{"chore":0,"member":0},{"chore":1,"member":0}]]

Output ONLY the JSON array. No text, no markdown.`
      },
      {
        role: 'user',
        content: `Members:\n${memberList}\n\nChores:\n${choreList}\n\nDays: ${input.numDays}`
      }
    ],
  });

  const text = completion.choices[0]?.message?.content || '[]';
  const cleaned = text.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();

  try {
    const parsed = JSON.parse(cleaned);
    if (!Array.isArray(parsed)) return [];
    return parsed;
  } catch {
    console.error('Failed to parse AI schedule:', cleaned.substring(0, 200));
    return [];
  }
}

export async function textToSpeechAudio(text: string): Promise<Buffer> {
  const response = await openai.audio.speech.create({
    model: 'tts-1',
    voice: 'nova',
    input: text,
    response_format: 'mp3',
    speed: 1.05,
  });

  const arrayBuffer = await response.arrayBuffer();
  return Buffer.from(arrayBuffer);
}
