"""Original synthesized placeholder score/effects. No samples or third-party recordings."""
from pathlib import Path
import math
import random
import struct
import wave

RATE = 22050
DEST = Path(__file__).resolve().parents[1] / '客户端/assets/audio'

def save(name, duration, sample):
    with wave.open(str(DEST / (name + '.wav')), 'wb') as out:
        out.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        out.writeframes(b''.join(struct.pack('<h', int(max(-1,min(1,sample(i/RATE)))*26000)) for i in range(int(duration*RATE))))

def pluck(t, hz):
    return math.sin(2*math.pi*hz*t)*math.exp(-t*7) + .2*math.sin(4*math.pi*hz*t)*math.exp(-t*12)

def main():
    DEST.mkdir(parents=True,exist_ok=True)
    save('ui',.12,lambda t: .4*pluck(t,880))
    save('repair',.6,lambda t: .3*(pluck(t,523.25)+pluck(t,783.99)))
    save('win',1.4,lambda t: sum(.25*pluck(t-k*.18,f) for k,f in enumerate([392,440,523.25,659.25]) if t>=k*.18))
    rng=random.Random(14)
    save('ink',.23,lambda t: (rng.random()-.5)*math.sin(math.pi*t/.23)*.5)
    save('hit',.3,lambda t: .7*math.sin(2*math.pi*(140*t-120*t*t))*math.exp(-t*14))
    notes=[261.63,392,349.23,440,392,329.63,261.63,293.66,329.63,392,523.25,440,392,329.63,293.66,261.63]
    def score(t):
        beat=int(t/.5)
        local=t% .5
        melody=.35*pluck(local,notes[beat%len(notes)])
        drum=.25*math.sin(2*math.pi*75*local)*math.exp(-local*35) if beat%2==0 else 0
        # Integer loop duration and a short endpoint fade prevent clicks.
        return (melody+drum)*min(1,t/.03,(16-t)/.05)
    save('battle',16,score)
    save('ambience',16,lambda t: (.025*math.sin(2*math.pi*196*t)+.012*math.sin(2*math.pi*294*t))*(.7+.3*math.sin(2*math.pi*t/16)))

if __name__ == '__main__': main()
