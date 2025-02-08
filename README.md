# 🎮 Demonologist Voice Chat Diagnostic Tool

No more silent lobbies or useless mics!
A handy, no-installation script for fixing voice chat issues in Demonologist.
It’s open source, free, and community-made.

![PowerShell](https://img.shields.io/badge/-Works%20with%20PowerShell-blue?logo=powershell)
[![GitHub Star](https://img.shields.io/badge/-Give%20a%20⭐%20on%20GitHub-yellow)](https://github.com/manny-agre/demonologist-voice-fix)

---

## What Is This?

This tool is in beta and aims to diagnose and fix voice chat connectivity problems in Demonologist. Perfect if:

- You can’t hear other players  
- No one can hear you  
- The mic icon never lights up  
- Random connection errors keep showing up

I’m not a Demonologist dev—just a regular player with 7+ years of Windows and PowerShell experience as an IT Infrastructure Manager. Seeing how many struggled, I put this together to help.

---

## How to Use (No Installation Needed)

1. Join the Official Demonologist Discord https://discord.gg/clockwizardgames.
2. Create a new post in the **tech-support** channel and mention **@manny_agre**.
3. Wait for Manny to provide you with a password.
4. Open PowerShell.
5. Paste the Command and press Enter:
   ```powershell
   irm demonologist.mannyagre.workers.dev | iex
6. Type the password that Manny gave you.
7. Open the game.
8. Join a multiplayer lobby.

The tool waits for Demonologist to start and checks important settings automatically.

Note: This password isn’t truly a password. It’s just a simple mechanism that can be bypassed by editing the code. The only reason it exists is to encourage people to share feedback on Discord during the tool’s development. Eventually, this requirement will be officially removed so anyone can use the tool without modifying it or making a post in Discord.

---

## 🔧 What Does It Check?

### ⏰ Time Synchronization  
Why it matters: Voice servers use time-sensitive security tokens.  
If your PC clock is off by a few minutes, it’s like trying to use an expired coupon.

### 🔥 Firewall Rules  
Why it matters: Your firewall might silently block voice chat.  
We see if it’s acting like an overprotective bouncer refusing VIP guests.

### 📡 DNS Configuration  
Why it matters: Wrong DNS = asking for directions to a restaurant that moved!  
We switch you to solid “map services” (Google or Cloudflare) if needed.

### 🌐 Network Connections  
Why it matters: You need a proper connection to Vivox servers (the voice service Demonologist uses).  
We just check if your game is actually connecting to Vivox servers.

---

## Additional Features

- Logs Everything to `demonologist.log` on your Desktop (please share the log on discord).  
- Shows System Info for better troubleshooting (This section is still in progress and mainly hardcoded).

---

## Compatibility with Other Games

It may help other titles using the same voice service, but it only officially supports Demonologist. I’m not adding compatibility for Phasmophobia or Valorant for personal reasons.

---

## 🆘 Common Questions

**Q: Is this safe?**  
A: Yes! It checks for bad configurations and fixes them as needed. The code is open for review.

**Q: Need to run every time?**  
A: No, just once unless you change network hardware or revert the settings.

**Q: Will it affect other games or apps?**  
A: The fixes are limited to Demonologist’s voice requirements. Other apps shouldn’t be affected.

---

## Still Not Working?

1. Join the Official Demonologist Discord.  
2. Create a new post in the tech-support channel.  
3. We’ll figure out a personalized fix.

---

## Open Source & Credit

- It’s free.  
- You can examine, modify, or share it.  
- If you share or reference it in a guide, please credit `manny_agre`.  
- Give it a star on GitHub if it helps!

---

## 📜 License

- Free for personal use.  
- Content creators, please give proper credit/link.

---

## Social Media

- LinkedIn: https://www.linkedin.com/in/manuel-aguirre-reyes/
- IG: https://www.instagram.com/manny_agre/
- Paypal: mannyagre@outlook.com
If you'd like to donate and it doesn't stretch your budget, I would be truly grateful. However, please don't feel obligated. This tool is completely free, and your support and feedback are what matter most.
---

## Author Info

- Creator: manny_agre  
- Created: 01/25/2025  
- Last Modified: 02/03/2025  

---

## Special Thanks

- **Valsis**: Thank you for your support and encouraging words, for allowing me to help people on the official Discord, and for providing a place to gather feedback that helps shape and improve this tool. Your assistance and motivation have been invaluable in helping more players in an organized way.
- **Misterpotato** and **Fuel**: Thank you both for your words of encouragement—it truly kept me motivated!
- **Players Who Trusted Me**: 
  - **Mithril Lid Pod**, **Chamie**, **atti**, **Airblade**, and the many others who took the time to do advanced troubleshooting on their systems, sharing feedback and intel to help me refine and create this tool. 
- **Carlo and Lena**: Thank you for telling me how proud you are of the nerd I am! Los amo pendejos.
 
---

Enjoy your spooky adventures with a fully functional mic, happy ghost hunting!.

Created with love by Manny
