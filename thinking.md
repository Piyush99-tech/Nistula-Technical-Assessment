# Part 3 — Thinking answers  
**Scenario:** 3am. Guest at Villa B1 on WhatsApp: no hot water, guests for breakfast in ~4 hours, calls it unacceptable, wants refund for tonight.

**A — What goes back on WhatsApp right now**  
Hi — sorry you’re dealing with no hot water this close to breakfast, that’s genuinely rough. I’ve escalated this as urgent for Villa B1 and pinged whoever’s on duty so someone can call or message you as soon as they can. I can’t approve refunds from this chat; a manager will handle that part properly once they’re on it. If anything feels unsafe (electrical smell, etc.), say so here.

Why: sounds human, doesn’t fake a refund or hot water fix in 30 seconds, still shows we’re not sleeping on it and splits “fix now” vs “money talk.”

**B — What the platform does after that send**  
Store the inbound (time, channel, body, Villa B1, booking if we have it). Classifier already screams complaint + refund → route escalate, don’t auto-send fluff. Open a P1 ticket, wake or SMS the duty manager / ops (caretaker hours don’t cover 3am — you need a night roster). Log who got notified and when. If nobody acknowledges the ticket in 30 minutes, hit backup on-call, bump the ticket, and send the guest one short follow-up: still on it, sorry for the wait — not another essay. If a human still hasn’t engaged, keep escalating the *people* side; don’t promise compensation in automation.

**C — Third hot-water complaint in two months**  
Treat it as a property problem, not bad luck. Tag Villa B1 + “hot water,” force a maintenance visit before next check-ins, and put a checklist item on every turnover (geyser, breaker, pressure, winter settings). I’d add a simple rule: same issue N times in M days → block self-check-in until ops signs off, or send a pre-arrival SMS: “If hot water acts up, call X first.” Fourth complaint drops because you fixed the kit and set expectations — not because the AI got better at apologising.
