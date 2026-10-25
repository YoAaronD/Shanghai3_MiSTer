#!/usr/bin/env python3
"""Frame pacing from a board trace (sim/tb_main --trace): updates per second,
the game's own work per update and the blitter's drawing time, per second.

How the game paces itself (68000 code, found with MAME's disassembler):
  * main loop, end of each update: sets the flag 307906 = 1 and spins until
    the vblank IRQ bumps the frame counter 307CE6, then clears the flag;
  * vblank IRQ (17E4): only if the flag is set, it starts the blitter
    (write 200008), bumps 307CE6 and reads the inputs; the music driver
    runs on every IRQ regardless.
An update that isn't finished by the next vblank therefore waits a whole
extra frame: that screen drops to 30 updates per second.

  frame_budget.py TRACE [--window FRAMES]
Columns: frames, updates (blitter starts), work = vblank IRQ to the main
loop's wait flag (includes any CPU hold), busy = blitter start to done (our
blitter, including the wait for the display-buffer copy).
"""
import argparse, bisect
ap=argparse.ArgumentParser(); ap.add_argument('trace'); ap.add_argument('--window',type=int,default=30)
a=ap.parse_args()
F=1e6*512*262*12/96e6
irq=[];won=[];busy=[];done=[];go=[]
for l in open(a.trace):
    p=l.split()
    if len(p)<3: continue
    if p[1]=='EV':
        if   p[2]=='IRQ_ACK':    irq.append(float(p[0]))
        elif p[2]=='BLIT_BUSY':  busy.append(float(p[0]))
        elif p[2]=='BLIT_DONE':  done.append(float(p[0]))
        elif p[2]=='BLITTER_GO': go.append(float(p[0]))
    elif p[1]=='W' and p[2]=='307906' and p[3]=='0001': won.append(float(p[0]))
med=lambda x: sorted(x)[len(x)//2] if x else float('nan')
for s in range(0,len(irq)-a.window,a.window):
    W=[];B=[]
    t0s,t1s=irq[s],irq[s+a.window]
    n_go=bisect.bisect_left(go,t1s)-bisect.bisect_left(go,t0s)
    for i in range(s,s+a.window):
        t0,t1=irq[i],irq[i+1]
        j=bisect.bisect_left(won,t0)
        if j<len(won) and won[j]<t1: W.append((won[j]-t0)/F*100)
        k=bisect.bisect_left(busy,t0)
        if k<len(busy) and busy[k]<t1:
            m=bisect.bisect_left(done,busy[k])
            if m<len(done): B.append((done[m]-busy[k])/F*100)
    rate=n_go/((t1s-t0s)/1e6)
    print('t=%6.1fs frame %5d  updates/s %5.1f  work %5.1f%%  busy %5.1f%%'%(t0s/1e6,int(t0s/F),rate,med(W),med(B)))
