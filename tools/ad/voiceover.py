#!/usr/bin/env python3
"""
Generate the phone ad's voiceover with ElevenLabs, one file per caption
(2026-10-06). Separate files so each line can be placed on its own beat.

    export ELEVENLABS_API_KEY=...       # your key, never commit it
    export ELEVENLABS_VOICE_ID=...      # Voices > the voice's ... menu > Copy voice ID
    python3 tools/ad/voiceover.py [outdir]   # default ~/Desktop/808-ad-voice

Writes 01.mp3 ... 08.mp3. Spoken as the user, not as Otto: someone showing
their phone to a friend, casual and a little deadpan.
"""
import json, os, sys, urllib.request

LINES = [
    "My meditation app won't let me open Instagram.",
    "Then it texts me.",
    "He forces me to meditate every day to open my apps.",
    "If I meditate every day, he gets happier.",
    "And my streak keeps growing.",
    "Every session earns coins...",
    "so I can buy Otto new hats.",
    "Make meditation a habit with 808 Meditate. On the App Store today.",
]

def main():
    key = os.environ.get("ELEVENLABS_API_KEY")
    voice = os.environ.get("ELEVENLABS_VOICE_ID")
    if not key or not voice:
        sys.exit("set ELEVENLABS_API_KEY and ELEVENLABS_VOICE_ID first")
    model = os.environ.get("ELEVENLABS_MODEL", "eleven_multilingual_v2")
    out = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/Desktop/808-ad-voice")
    os.makedirs(out, exist_ok=True)
    for i, text in enumerate(LINES, 1):
        body = {
            "text": text,
            "model_id": model,
            # Loose and expressive, so it sounds like a person, not a narrator.
            "voice_settings": {"stability": 0.35, "similarity_boost": 0.8, "style": 0.35,
                               "use_speaker_boost": True, "speed": 1.05},
        }
        req = urllib.request.Request(
            "https://api.elevenlabs.io/v1/text-to-speech/%s?output_format=mp3_44100_128" % voice,
            data=json.dumps(body).encode(),
            headers={"xi-api-key": key, "Content-Type": "application/json", "Accept": "audio/mpeg"})
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                audio = r.read()
        except urllib.error.HTTPError as e:
            sys.exit("line %d failed: %s %s" % (i, e.code, e.read()[:300].decode(errors="replace")))
        path = os.path.join(out, "%02d.mp3" % i)
        open(path, "wb").write(audio)
        print("wrote", path, "-", text)
    print("done:", out)

if __name__ == "__main__":
    main()
