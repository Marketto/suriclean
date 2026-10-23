/* Suri the meerkat as an animated SVG, shared by the desktop app (Tauri) and the website.
   Same 220×260 geometry as the native macOS version.
   Usage: el.innerHTML = Suri.svg(); Suri.setActivity(el, "digging"); */
(function () {
  const FUR = "#E6B880", LIGHT = "#FAE6C2", DARK = "#734D36", PINK = "#FF80A8", BLUSH = "#FF96AF", COCOA = "#54382B";

  const css = `
  .suri svg{overflow:visible;display:block;width:100%;height:100%}
  .suri .t-origin{transform-box:view-box}
  .suri .body-all{transform-origin:110px 250px;animation:suri-breath 2.8s ease-in-out infinite}
  .suri .head{transform-origin:110px 94px;animation:suri-look 9s ease-in-out infinite}
  .suri .eye{transform-box:fill-box;transform-origin:center;animation:suri-blink 3.9s infinite}
  .suri .pupils{animation:suri-eyes 7s ease-in-out infinite}
  .suri .tail{transform-origin:140px 228px;animation:suri-tail 3.6s ease-in-out infinite}
  .suri .arm-r{transform-origin:144px 138px;transform:rotate(-12deg)}
  .suri .arm-l{transform-origin:76px 138px;transform:rotate(12deg)}
  .suri .prop,.suri .hat,.suri .fx,.suri .front,.suri .back,.suri .eyes-closed,.suri .eyes-happy,.suri .mouth-open{display:none}
  .suri[data-act="idle"] .arm-r{animation:suri-hello 9s ease-in-out infinite}
  .suri[data-act="wave"] .arm-r{animation:suri-wave .5s ease-in-out infinite}
  .suri[data-act="wave"] .mouth-open{display:inline}.suri[data-act="wave"] .mouth-w{display:none}

  .suri[data-act="digging"] .body-all{animation:suri-dig-body .4s ease-in-out infinite;transform:rotate(8deg)}
  .suri[data-act="digging"] .arm-r{animation:suri-dig-arm .4s ease-in-out infinite}
  .suri[data-act="digging"] .p-shovel,.suri[data-act="digging"] .fx-dirt,.suri[data-act="digging"] .back-mound{display:inline}
  .suri[data-act="digging"] .pupils{animation:none;transform:translate(3px,3px)}

  .suri[data-act="detective"] .arm-r{transform:rotate(165deg);animation:suri-mag 2s ease-in-out infinite}
  .suri[data-act="detective"] .p-magnifier,.suri[data-act="detective"] .h-detective,.suri[data-act="detective"] .fx-question{display:inline}
  .suri[data-act="detective"] .body-all{animation:suri-sway 4s ease-in-out infinite}

  .suri[data-act="sweeping"] .arm-r{animation:suri-sweep .55s ease-in-out infinite}
  .suri[data-act="sweeping"] .arm-l{animation:suri-sweep-l .55s ease-in-out infinite}
  .suri[data-act="sweeping"] .p-broom,.suri[data-act="sweeping"] .fx-dust,.suri[data-act="sweeping"] .mouth-open{display:inline}
  .suri[data-act="sweeping"] .mouth-w{display:none}
  .suri[data-act="sweeping"] .body-all{animation:suri-sway .55s ease-in-out infinite}

  .suri[data-act="reading"] .arm-r{transform:rotate(40deg)}.suri[data-act="reading"] .arm-l{transform:rotate(-40deg)}
  .suri[data-act="reading"] .f-book{display:inline}
  .suri[data-act="reading"] .pupils{animation:suri-read 1.2s ease-in-out infinite}

  .suri[data-act="sleepy"] .eyes-open{display:none}.suri[data-act="sleepy"] .eyes-closed{display:inline}
  .suri[data-act="sleepy"] .h-nightcap,.suri[data-act="sleepy"] .fx-zzz{display:inline}
  .suri[data-act="sleepy"] .head{animation:suri-nod 3s ease-in-out infinite}
  .suri[data-act="sleepy"] .arm-r,.suri[data-act="sleepy"] .arm-l{animation:none}

  .suri[data-act="hacking"] .arm-r{animation:suri-type-r .13s linear infinite}
  .suri[data-act="hacking"] .arm-l{animation:suri-type-l .13s linear infinite}
  .suri[data-act="hacking"] .f-laptop,.suri[data-act="hacking"] .fx-bits{display:inline}
  .suri[data-act="hacking"] .pupils{animation:none;transform:translateY(3px)}

  .suri[data-act="sniffing"] .nose{transform-box:fill-box;transform-origin:center;animation:suri-sniff .25s ease-in-out infinite}
  .suri[data-act="sniffing"] .head{animation:suri-tilt 2.4s ease-in-out infinite}
  .suri[data-act="sniffing"] .arm-r{transform:rotate(22deg)}.suri[data-act="sniffing"] .arm-l{transform:rotate(-22deg)}
  .suri[data-act="sniffing"] .fx-scent{display:inline}

  .suri[data-act="lookout"] .body-all{animation:suri-stretch 2.6s ease-in-out infinite}
  .suri[data-act="lookout"] .head{animation:suri-scan 3.5s ease-in-out infinite}
  .suri[data-act="lookout"] .arm-r{transform:rotate(25deg)}.suri[data-act="lookout"] .arm-l{transform:rotate(-25deg)}
  .suri[data-act="lookout"] .back-hill,.suri[data-act="lookout"] .fx-alert{display:inline}

  .suri[data-act="celebrating"] .body-all{animation:suri-jump .6s ease-in-out infinite}
  .suri[data-act="celebrating"] .arm-r{animation:suri-cheer-r .3s ease-in-out infinite}
  .suri[data-act="celebrating"] .arm-l{animation:suri-cheer-l .3s ease-in-out infinite}
  .suri[data-act="celebrating"] .eyes-open{display:none}.suri[data-act="celebrating"] .eyes-happy{display:inline}
  .suri[data-act="celebrating"] .h-party,.suri[data-act="celebrating"] .fx-sparkle,.suri[data-act="celebrating"] .mouth-open{display:inline}
  .suri[data-act="celebrating"] .mouth-w{display:none}
  .suri[data-act="celebrating"] .tail{animation:suri-tail .3s ease-in-out infinite}

  .suri .fx-dirt circle{animation:suri-dirt 0.62s ease-out infinite}
  .suri .fx-dust circle{transform-box:fill-box;transform-origin:center;animation:suri-dust 1.1s ease-out infinite}
  .suri .fx-zzz text{animation:suri-z 2.9s ease-in infinite}
  .suri .fx-bits text{animation:suri-bits 1.7s linear infinite}
  .suri .fx-scent circle{animation:suri-scent 1.4s linear infinite}
  .suri .fx-question{animation:suri-q 2.5s ease-in-out infinite}
  .suri .fx-alert{animation:suri-alert 2s steps(1) infinite}
  .suri .fx-sparkle text{transform-box:fill-box;transform-origin:center;animation:suri-twinkle 1s ease-in-out infinite}
  .suri .page{transform-box:fill-box;transform-origin:left center;animation:suri-page 3s ease-in-out infinite}

  @keyframes suri-breath{0%,100%{transform:scale(1,1)}50%{transform:scale(.99,1.012)}}
  @keyframes suri-look{0%,100%{transform:rotate(0)}25%{transform:rotate(-4deg)}75%{transform:rotate(4deg)}}
  @keyframes suri-blink{0%,96%,100%{transform:scaleY(1)}97.5%{transform:scaleY(.1)}}
  @keyframes suri-eyes{0%,100%{transform:translateX(0)}30%{transform:translateX(-3px)}70%{transform:translateX(3px)}}
  @keyframes suri-tail{0%,100%{transform:rotate(-6deg)}50%{transform:rotate(6deg)}}
  @keyframes suri-hello{0%,80%,100%{transform:rotate(-12deg)}84%,92%{transform:rotate(-140deg)}88%,96%{transform:rotate(-165deg)}}
  @keyframes suri-wave{0%,100%{transform:rotate(-135deg)}50%{transform:rotate(-168deg)}}
  @keyframes suri-dig-body{0%,100%{transform:rotate(8deg) translateY(0)}50%{transform:rotate(8deg) translateY(-2px)}}
  @keyframes suri-dig-arm{0%,100%{transform:rotate(-10deg)}50%{transform:rotate(-60deg)}}
  @keyframes suri-mag{0%,100%{transform:rotate(162deg)}50%{transform:rotate(168deg)}}
  @keyframes suri-sway{0%,100%{transform:translateX(-6px) rotate(-2deg)}50%{transform:translateX(6px) rotate(2deg)}}
  @keyframes suri-sweep{0%,100%{transform:rotate(48deg)}50%{transform:rotate(-8deg)}}
  @keyframes suri-sweep-l{0%,100%{transform:rotate(-50deg)}50%{transform:rotate(-10deg)}}
  @keyframes suri-read{0%,100%{transform:translate(-3px,3px)}50%{transform:translate(3px,3px)}}
  @keyframes suri-nod{0%,100%{transform:rotate(10deg) translateY(0)}50%{transform:rotate(12deg) translateY(3px)}}
  @keyframes suri-type-r{0%,100%{transform:rotate(27deg)}50%{transform:rotate(37deg)}}
  @keyframes suri-type-l{0%,100%{transform:rotate(-37deg)}50%{transform:rotate(-27deg)}}
  @keyframes suri-sniff{0%,100%{transform:scale(1)}50%{transform:scale(1.22)}}
  @keyframes suri-tilt{0%,100%{transform:rotate(-10deg)}50%{transform:rotate(10deg)}}
  @keyframes suri-stretch{0%,100%{transform:scale(.96,1.05)}50%{transform:scale(.95,1.065)}}
  @keyframes suri-scan{0%,100%{transform:rotate(-8deg)}50%{transform:rotate(8deg)}}
  @keyframes suri-jump{0%,100%{transform:translateY(0) scale(1.04,.94)}15%{transform:translateY(0) scale(1,1)}50%{transform:translateY(-24px) scale(.98,1.03)}}
  @keyframes suri-cheer-r{0%,100%{transform:rotate(-140deg)}50%{transform:rotate(-165deg)}}
  @keyframes suri-cheer-l{0%,100%{transform:rotate(165deg)}50%{transform:rotate(140deg)}}
  @keyframes suri-dirt{0%{transform:translate(0,0);opacity:1}100%{transform:translate(var(--dx),0);opacity:0}}
  @keyframes suri-dust{0%{transform:translateY(0) scale(.4);opacity:.6}100%{transform:translateY(-45px) scale(1.6);opacity:0}}
  @keyframes suri-z{0%{transform:translate(0,0);opacity:0}20%{opacity:1}100%{transform:translate(30px,-55px);opacity:0}}
  @keyframes suri-bits{0%{transform:translateY(0);opacity:0}20%{opacity:1}100%{transform:translateY(-120px);opacity:0}}
  @keyframes suri-scent{0%{transform:translateX(0);opacity:0}30%{opacity:1}100%{transform:translateX(-80px);opacity:0}}
  @keyframes suri-q{0%,100%{transform:translateY(0);opacity:0}50%{transform:translateY(-14px);opacity:1}}
  @keyframes suri-alert{0%{opacity:1}30%{opacity:0}}
  @keyframes suri-twinkle{0%,100%{transform:scale(.6) rotate(0);opacity:.4}50%{transform:scale(1.2) rotate(45deg);opacity:1}}
  @keyframes suri-page{0%,80%,100%{transform:scaleX(1)}90%{transform:scaleX(-1)}}
  `;

  function injectCSS() {
    if (document.getElementById("suri-css")) return;
    const s = document.createElement("style");
    s.id = "suri-css";
    s.textContent = css;
    document.head.appendChild(s);
  }

  function arm(side, propSVG) {
    const x = side === "r" ? 144 : 76;
    return `<g class="t-origin arm-${side}">
      ${propSVG || ""}
      <rect x="${x - 9}" y="138" width="18" height="52" rx="9" fill="${FUR}"/>
      <circle cx="${x}" cy="184" r="8" fill="${LIGHT}"/>
    </g>`;
  }

  function svg() {
    injectCSS();
    const shovel = `<g class="prop p-shovel"><rect x="141" y="182" width="6" height="36" rx="3" fill="#9E6B42"/><path d="M132 216h24q0 22-12 26q-12-4-12-26z" fill="#BDBDBD"/></g>`;
    const magnifier = `<g class="prop p-magnifier"><rect x="140.5" y="184" width="7" height="16" rx="3" fill="#9E6B42"/><circle cx="144" cy="216" r="16.5" fill="rgba(108,178,255,.35)" stroke="#8C8C8C" stroke-width="5"/><circle cx="137" cy="209" r="4" fill="#fff"/></g>`;
    const broom = `<g class="prop p-broom"><rect x="141.5" y="182" width="5" height="40" rx="2.5" fill="#9E6B42"/><rect x="133" y="221" width="22" height="6" rx="3" fill="#FF786E"/><path d="M134 227h20l10 26h-40z" fill="#FFD14D"/></g>`;
    return `<svg viewBox="0 0 220 260" xmlns="http://www.w3.org/2000/svg" aria-label="Suri la suricata">
  <g class="back back-mound"><ellipse cx="180" cy="248" rx="42" ry="14" fill="#9E7350"/><ellipse cx="180" cy="244" rx="23" ry="6" fill="#6F5038"/></g>
  <g class="back back-hill"><ellipse cx="110" cy="254" rx="105" ry="23" fill="#F5D99E"/></g>
  <ellipse cx="110" cy="249" rx="60" ry="8" fill="rgba(115,77,54,.16)"/>
  <g class="body-all t-origin">
    <g class="tail t-origin"><path d="M135 232C190 242 205 190 193 150" fill="none" stroke="${FUR}" stroke-width="16" stroke-linecap="round"/><path d="M191 160L193 150" stroke="${DARK}" stroke-width="16" stroke-linecap="round"/></g>
    <ellipse cx="88" cy="240" rx="19" ry="9" fill="${FUR}"/><ellipse cx="132" cy="240" rx="19" ry="9" fill="${FUR}"/>
    <ellipse cx="110" cy="178" rx="48" ry="65" fill="${FUR}"/><ellipse cx="110" cy="190" rx="30" ry="46" fill="${LIGHT}"/>
    <g class="head t-origin">
      <circle cx="58" cy="70" r="14" fill="${DARK}"/><circle cx="162" cy="70" r="14" fill="${DARK}"/>
      <circle cx="58" cy="70" r="6.5" fill="${BLUSH}"/><circle cx="162" cy="70" r="6.5" fill="${BLUSH}"/>
      <ellipse cx="110" cy="92" rx="60" ry="50" fill="${FUR}"/>
      <rect x="104" y="43" width="12" height="26" rx="6" fill="rgba(115,77,54,.22)"/>
      <ellipse cx="110" cy="113" rx="28" ry="19" fill="${LIGHT}"/>
      <ellipse cx="82" cy="88" rx="19" ry="23" fill="${DARK}" transform="rotate(20 82 88)"/>
      <ellipse cx="138" cy="88" rx="19" ry="23" fill="${DARK}" transform="rotate(-20 138 88)"/>
      <g class="eyes-open"><g class="pupils">
        <g class="eye"><ellipse cx="82" cy="89" rx="13" ry="15" fill="#000"/><circle cx="77" cy="82" r="5.5" fill="#fff"/><circle cx="87" cy="96" r="2.5" fill="#fff"/></g>
        <g class="eye"><ellipse cx="138" cy="89" rx="13" ry="15" fill="#000"/><circle cx="133" cy="82" r="5.5" fill="#fff"/><circle cx="143" cy="96" r="2.5" fill="#fff"/></g>
      </g></g>
      <g class="eyes-closed" fill="none" stroke="#000" stroke-width="3" stroke-linecap="round"><path d="M72 88q10 12 20 0"/><path d="M128 88q10 12 20 0"/></g>
      <g class="eyes-happy" fill="none" stroke="#000" stroke-width="3.5" stroke-linecap="round"><path d="M72 94q10-16 20 0"/><path d="M128 94q10-16 20 0"/></g>
      <ellipse cx="64" cy="116" rx="11" ry="6" fill="rgba(255,128,168,.5)"/><ellipse cx="156" cy="116" rx="11" ry="6" fill="rgba(255,128,168,.5)"/>
      <path class="nose" d="M104 99.5h12q4 0-6 11q-10-11-6-11z" fill="${COCOA}"/>
      <path class="mouth-w" d="M101 112q4.5 9 9 0q4.5 9 9 0" fill="none" stroke="${COCOA}" stroke-width="2.2" stroke-linecap="round"/>
      <path class="mouth-open" d="M102 114h16q-1 13-8 13t-8-13z" fill="#FF786E"/>
      <g class="hat h-detective"><rect x="57" y="46" width="106" height="12" rx="6" fill="#664A33"/><path d="M71 52q39-72 78 0z" fill="#8F6E4F"/><rect x="71" y="43.5" width="78" height="7" rx="3.5" fill="#FF786E"/></g>
      <g class="hat h-nightcap"><path d="M72 58Q102-6 172-6Q157 26 162 58z" fill="#A88FFA"/><rect x="59" y="43" width="98" height="14" rx="7" fill="#fff"/><circle cx="172" cy="-4" r="8" fill="#fff"/></g>
      <g class="hat h-party"><path d="M110-3L132 47H88z" fill="#FF80A8"/><path d="M98 25h24M93 37h34" stroke="#FFD14D" stroke-width="4"/><circle cx="110" cy="-4" r="6.5" fill="#6CB2FF"/></g>
    </g>
    <g class="front f-book"><rect x="67" y="147" width="86" height="58" rx="5" fill="${PINK}"/><rect x="71" y="151" width="38" height="50" rx="3" fill="#fff"/><rect x="111" y="151" width="38" height="50" rx="3" fill="#fff"/>
      <g fill="rgba(84,56,43,.15)"><rect x="77" y="160" width="26" height="3" rx="1.5"/><rect x="77" y="169" width="26" height="3" rx="1.5"/><rect x="77" y="178" width="26" height="3" rx="1.5"/><rect x="117" y="160" width="26" height="3" rx="1.5"/><rect x="117" y="169" width="26" height="3" rx="1.5"/><rect x="117" y="178" width="26" height="3" rx="1.5"/></g>
      <rect class="page" x="110" y="151" width="38" height="50" rx="3" fill="#EEE"/></g>
    <g class="front f-laptop"><rect x="70" y="151" width="80" height="54" rx="6" fill="#CCC"/><path d="M110 184l-8-8a5 5 0 0 1 8-6a5 5 0 0 1 8 6z" fill="${PINK}"/><rect x="63" y="204" width="94" height="8" rx="3" fill="#9E9E9E"/><circle cx="142" cy="200" r="2.5" fill="#61D6AD"/></g>
    ${arm("l", "")}
    ${arm("r", shovel + magnifier + broom)}
  </g>
  <g class="fx fx-dirt" fill="#9E7350">${[0, 1, 2, 3, 4, 5].map(i => `<circle cx="180" cy="${236 - i * 6}" r="${3.5 + (i % 3)}" style="--dx:${24 + i * 6}px;animation-delay:${i * 0.1}s"/>`).join("")}</g>
  <g class="fx fx-dust" fill="rgba(150,150,150,.35)">${[0, 1, 2, 3, 4].map(i => `<circle cx="${70 + i * 18}" cy="244" r="9" style="animation-delay:${i * 0.2}s"/>`).join("")}</g>
  <g class="fx fx-zzz" fill="#7A64C8" font-family="ui-rounded,system-ui,sans-serif" font-weight="900">${[0, 1, 2].map(i => `<text x="158" y="62" font-size="${16 + i * 5}" style="animation-delay:${i * 0.95}s">z</text>`).join("")}</g>
  <g class="fx fx-bits" fill="#3FA582" font-family="monospace" font-weight="700" font-size="13">${[0, 1, 2, 3, 4, 5].map(i => `<text x="${70 + i * 15}" y="165" style="animation-delay:${i * 0.28}s">${i % 2}</text>`).join("")}</g>
  <g class="fx fx-scent" fill="#FFD14D">${[0, 1, 2, 3].map(i => `<circle cx="212" cy="${106 + (i % 2) * 8}" r="3" style="animation-delay:${i * 0.35}s"/>`).join("")}</g>
  <text class="fx fx-question" x="180" y="54" font-size="26" font-weight="900" fill="#7A64C8" font-family="ui-rounded,system-ui,sans-serif">?</text>
  <text class="fx fx-alert" x="176" y="44" font-size="28" font-weight="900" fill="#FF786E" font-family="ui-rounded,system-ui,sans-serif">!</text>
  <g class="fx fx-sparkle">${[0, 1, 2, 3, 4, 5].map(i => { const a = i * Math.PI / 3; return `<text x="${110 + Math.cos(a) * 100}" y="${130 + Math.sin(a) * 100}" font-size="${14 + (i % 3) * 5}" fill="${["#FF80A8", "#FFD14D", "#6CB2FF"][i % 3]}" style="animation-delay:${i * 0.15}s">✦</text>`; }).join("")}</g>
</svg>`;
  }

  function mount(el, activity) {
    el.classList.add("suri");
    el.innerHTML = svg();
    el.dataset.act = activity || "idle";
  }

  function setActivity(el, activity) {
    if (!el.classList.contains("suri")) mount(el, activity);
    el.dataset.act = activity || "idle";
  }

  window.Suri = { svg, mount, setActivity };
})();
