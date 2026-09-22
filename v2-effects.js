(() => {
  const state = {
    sound: localStorage.getItem("onomatope_sound") !== "off",
    lastSignature: "",
    lastRound: null,
    audio: null
  };

  function audioCtx() {
    if (!state.audio) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (AC) state.audio = new AC();
    }
    return state.audio;
  }

  function tone(freq=440, duration=.08, type="sine", volume=.045, delay=0) {
    if (!state.sound) return;
    const ctx = audioCtx();
    if (!ctx) return;
    try {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = type;
      osc.frequency.value = freq;
      gain.gain.setValueAtTime(volume, ctx.currentTime + delay);
      gain.gain.exponentialRampToValueAtTime(.0001, ctx.currentTime + delay + duration);
      osc.connect(gain); gain.connect(ctx.destination);
      osc.start(ctx.currentTime + delay);
      osc.stop(ctx.currentTime + delay + duration);
    } catch {}
  }

  const sounds = {
    start(){ tone(520,.08,"square",.035); tone(660,.08,"square",.035,.11); tone(880,.13,"square",.04,.22); },
    buzz(){ tone(180,.05,"sawtooth",.05); tone(520,.12,"square",.04,.04); },
    correct(){ tone(523,.09,"sine",.05); tone(659,.09,"sine",.05,.1); tone(784,.18,"sine",.05,.2); },
    wrong(){ tone(210,.13,"sawtooth",.035); tone(155,.2,"sawtooth",.035,.12); },
    final(){ tone(330,.1,"square",.035); tone(440,.1,"square",.035,.12); tone(660,.25,"square",.04,.24); }
  };

  function ensureToggle() {
    const b = document.getElementById("soundToggle");
    if (!b || b.dataset.bound) return;
    b.dataset.bound = "1";
    b.textContent = state.sound ? "🔊" : "🔇";
    b.onclick = () => {
      state.sound = !state.sound;
      localStorage.setItem("onomatope_sound", state.sound ? "on" : "off");
      b.textContent = state.sound ? "🔊" : "🔇";
      if (state.sound) tone(660,.08);
    };
  }

  function overlay(html, cls="") {
    document.querySelector(".v2Overlay")?.remove();
    const el = document.createElement("div");
    el.className = `v2Overlay ${cls}`;
    el.innerHTML = html;
    document.body.appendChild(el);
    requestAnimationFrame(() => el.classList.add("show"));
    setTimeout(() => {
      el.classList.remove("show");
      setTimeout(() => el.remove(), 280);
    }, 1050);
  }

  function confetti() {
    const box = document.createElement("div");
    box.className = "confettiBox";
    const chars = ["●","▲","■","★","◆","●","▲","■"];
    for (let i=0;i<36;i++) {
      const s = document.createElement("i");
      s.textContent = chars[i % chars.length];
      s.style.left = `${Math.random()*100}%`;
      s.style.animationDelay = `${Math.random()*.45}s`;
      s.style.animationDuration = `${1.4+Math.random()*1.2}s`;
      s.style.fontSize = `${10+Math.random()*18}px`;
      box.appendChild(s);
    }
    document.body.appendChild(box);
    setTimeout(()=>box.remove(),3000);
  }

  function enhanceWords() {
    const words = [...document.querySelectorAll(".word")];
    words.forEach((w,i)=>{
      if (!w.dataset.v2) {
        w.dataset.v2="1";
        w.classList.add("v2Word");
        w.style.animationDelay = `${i*.16}s`;
      }
    });
  }

  function addRoundBadge() {
    const qhead = document.querySelector(".qhead span");
    if (!qhead) return;
    const m = qhead.textContent.match(/(\d+)\s*\/\s*10/);
    if (!m) return;
    const round = Number(m[1]);
    if (round === 10 && !document.querySelector(".finalBadge")) {
      const badge = document.createElement("div");
      badge.className = "finalBadge";
      badge.textContent = "🔥 FINAL ROUND";
      document.querySelector(".qhead")?.after(badge);
      if (state.lastRound !== 10) {
        sounds.final();
        overlay("<b>FINAL ROUND</b><span>最後の一問！</span>","final");
      }
    }
    if (state.lastRound !== round && document.querySelector(".buzz")) {
      state.lastRound = round;
      sounds.start();
      overlay(`<b>ROUND ${round}</b><span>READY?</span>`, round===10 ? "final" : "");
    }
  }

  function enhanceBuzz() {
    const b = document.querySelector(".buzz");
    if (!b || b.dataset.v2) return;
    b.dataset.v2="1";
    b.innerHTML = `<span class="buzzIcon">⚡</span><span>早押し！</span><small>わかったらタップ</small>`;
    b.addEventListener("click", () => {
      sounds.buzz();
      b.classList.add("pressed");
      if (navigator.vibrate) navigator.vibrate(45);
      setTimeout(()=>b.classList.remove("pressed"),250);
    });
  }

  function enhanceTimer() {
    const t = document.querySelector(".timer");
    if (!t) return;
    const n = Number(t.textContent);
    if (n <= 3) t.classList.add("v2Danger");
  }

  function enhanceResult() {
    const result = document.querySelector(".resultPoint");
    if (!result || result.dataset.v2) return;
    result.dataset.v2="1";
    if (result.classList.contains("correct")) {
      sounds.correct();
      overlay("<b>正解！</b><span>NICE ANSWER!</span>","correct");
      confetti();
    } else if (result.classList.contains("wrong")) {
      sounds.wrong();
      overlay("<b>おしい！</b><span>NEXT CHANCE</span>","wrong");
    }
  }

  function enhanceRanking() {
    const ranks = [...document.querySelectorAll(".rank")];
    if (!ranks.length) return;
    ranks.forEach((r,i)=>{
      r.style.setProperty("--delay", `${i*.09}s`);
      r.classList.add("v2Rank");
    });
    const winner = document.querySelector(".winner");
    if (winner && !winner.dataset.v2) {
      winner.dataset.v2="1";
      winner.insertAdjacentHTML("afterbegin", `<div class="kingTitle">👑 オノマトペ王 👑</div>`);
      confetti();
      sounds.correct();
    }
  }

  function signature() {
    const app = document.getElementById("app");
    return app ? app.innerText.slice(0,300) : "";
  }

  function scan() {
    ensureToggle();
    const sig = signature();
    enhanceWords();
    addRoundBadge();
    enhanceBuzz();
    enhanceTimer();
    enhanceResult();
    enhanceRanking();

    if (sig !== state.lastSignature) {
      state.lastSignature = sig;
      document.querySelectorAll(".panel").forEach((p,i)=>{
        if (!p.dataset.entered) {
          p.dataset.entered="1";
          p.style.setProperty("--panel-delay",`${Math.min(i*.05,.15)}s`);
          p.classList.add("v2PanelIn");
        }
      });
    }
  }

  const obs = new MutationObserver(scan);
  obs.observe(document.documentElement,{subtree:true,childList:true,characterData:true});
  document.addEventListener("pointerdown",()=>{ try{audioCtx()?.resume()}catch{} },{once:true});
  scan();
  setInterval(scan,300);
})();