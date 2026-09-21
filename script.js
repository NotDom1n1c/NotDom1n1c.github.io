/* Dominic Aebersold — persönliche Seite
   Minimales, datenschutzfreundliches JS. Kein Tracking, keine externen Requests. */

(function () {
  "use strict";

  // Jahr im Footer aktuell halten
  var yearEl = document.getElementById("year");
  if (yearEl) yearEl.textContent = String(new Date().getFullYear());

  // Kleine Uhr / Ortszeit in der Hero-Metazeile
  var clockEl = document.getElementById("clock");
  if (clockEl) {
    var tick = function () {
      var now = new Date();
      var hh = String(now.getHours()).padStart(2, "0");
      var mm = String(now.getMinutes()).padStart(2, "0");
      clockEl.textContent = hh + ":" + mm + " Ortszeit";
    };
    tick();
    setInterval(tick, 30000);
  }

  // Ketten-Deko: LED-weisse, ineinander verwobene Kettenglieder als SVG.
  // Alle Glieder gleich ausgerichtet (eine Richtung), von den vier Ecken zum
  // Profilbild. Verweben: Glieder A zuerst, Glieder B darueber, dann die untere
  // Haelfte von A wieder oben drauf -> echtes Ueber/Unter.
  var deco = document.querySelector(".hero-chains");
  if (deco) {
    var NS = "http://www.w3.org/2000/svg";
    var H = 40, CY = 20;          // SVG-Hoehe / Mittellinie
    var A = 15, B = 9, TUBE = 5;  // Glied: halbe Laenge / halbe Hoehe / Rohrdicke
    var STEP = 15, N = 28;        // Abstand der Glieder / Punkte pro Ring
    var BX = 0.36, DRIFT = 9;     // Ansicht von oben (rad) / Twist pro Glied (Grad)

    function svgEl(name) { return document.createElementNS(NS, name); }

    function makeGradient(defs, gid) {
      var lg = svgEl("linearGradient");
      lg.setAttribute("id", gid);
      lg.setAttribute("gradientUnits", "userSpaceOnUse");
      lg.setAttribute("x1", "0"); lg.setAttribute("y1", "0");
      lg.setAttribute("x2", "0"); lg.setAttribute("y2", H);
      [["0", "#ffffff"], ["0.5", "#ffffff"], ["0.78", "#eef5ff"], ["1", "#d3e4f7"]]
        .forEach(function (s) {
          var st = svgEl("stop");
          st.setAttribute("offset", s[0]);
          st.setAttribute("stop-color", s[1]);
          lg.appendChild(st);
        });
      defs.appendChild(lg);
    }

    // Ein Kettenglied als echter 3D-Ring: die Schleife wird um theta um die
    // Kettenachse gedreht, dann leicht von oben betrachtet (BX) und orthografisch
    // projiziert. Punkte mit z >= 0 liegen vorne, z < 0 hinten -> echtes Verweben.
    function linkPoints(cx, theta) {
      var ct = Math.cos(theta), st = Math.sin(theta);
      var cb = Math.cos(BX), sb = Math.sin(BX);
      var pts = [];
      for (var k = 0; k <= N; k++) {
        var t = k / N * 2 * Math.PI;
        var lx = A * Math.cos(t), lb = B * Math.sin(t);
        var y1 = lb * ct, z1 = lb * st;   // Drehung um die Kettenachse (x)
        var y2 = y1 * cb - z1 * sb;       // leicht von oben
        var z2 = y1 * sb + z1 * cb;
        pts.push({ x: cx + lx, y: CY + y2, z: z2 });
      }
      return pts;
    }

    function runPath(run) {
      var d = "M";
      for (var i = 0; i < run.length; i++) {
        d += (i ? "L" : "") + run[i].x.toFixed(1) + " " + run[i].y.toFixed(1);
      }
      return d;
    }

    function pushRun(run, near, gNear, gFar, gid) {
      if (run.length < 2) return;
      var p = svgEl("path");
      p.setAttribute("d", runPath(run));
      p.setAttribute("fill", "none");
      p.setAttribute("stroke-linecap", "round");
      p.setAttribute("stroke-linejoin", "round");
      if (near) {
        p.setAttribute("stroke", "url(#" + gid + ")");
        p.setAttribute("stroke-width", TUBE);
        gNear.appendChild(p);
      } else {
        p.setAttribute("stroke", "#b9c9db"); // hinten: kuehler/dunkler fuer Tiefe
        p.setAttribute("stroke-width", TUBE * 0.8);
        gFar.appendChild(p);
      }
    }

    // Ring in zusammenhaengende Vorne/Hinten-Stuecke schneiden
    function addRuns(pts, gNear, gFar, gid) {
      var n = pts.length, i, start = 0;
      for (i = 1; i < n; i++) {
        if ((pts[i].z >= 0) !== (pts[i - 1].z >= 0)) { start = i; break; }
      }
      var cur = [pts[start]], side = pts[start].z >= 0;
      for (i = 1; i < n; i++) {
        var p = pts[(start + i) % n], sd = p.z >= 0;
        cur.push(p);
        if (sd !== side) { pushRun(cur, side, gNear, gFar, gid); cur = [p]; side = sd; }
      }
      pushRun(cur, side, gNear, gFar, gid);
    }

    var chainCount = 0;
    function makeChain(len) {
      var id = chainCount++, gid = "g" + id;
      var div = document.createElement("div");
      div.className = "chain";
      var svg = svgEl("svg");
      svg.setAttribute("width", len); svg.setAttribute("height", H);
      svg.setAttribute("viewBox", "0 0 " + len + " " + H);
      var defs = svgEl("defs"); makeGradient(defs, gid); svg.appendChild(defs);

      var gFar = svgEl("g"), gNear = svgEl("g");
      var nLinks = Math.floor(len / STEP) + 1;
      for (var i = 0; i <= nLinks; i++) {
        var theta = (i * (90 + DRIFT)) * Math.PI / 180; // 90 = Verhaken, DRIFT = Twist
        addRuns(linkPoints(i * STEP, theta), gNear, gFar, gid);
      }
      svg.appendChild(gFar);  // hinten zuerst
      svg.appendChild(gNear); // vorne drueber -> Verweben
      div.appendChild(svg);
      return div;
    }

    function buildChains() {
      deco.innerHTML = "";
      chainCount = 0;
      var dr = deco.getBoundingClientRect();
      var avEl = document.querySelector(".avatar");
      if (!avEl) return;
      var av = avEl.getBoundingClientRect();
      var cx = dr.width / 2;
      var cy = (av.top - dr.top) + av.height / 2;
      var corners = [[0, 0], [dr.width, 0], [0, dr.height], [dr.width, dr.height]];
      corners.forEach(function (c) {
        var dx = c[0] - cx, dy = c[1] - cy;
        var dist = Math.sqrt(dx * dx + dy * dy) + 40; // etwas ueber die Ecke hinaus
        var ang = Math.atan2(dy, dx) * 180 / Math.PI;
        var d = makeChain(dist);
        d.style.left = cx + "px";
        d.style.top = cy + "px";
        d.style.transform = "rotate(" + ang + "deg)";
        deco.appendChild(d);
      });
    }

    buildChains();
    window.addEventListener("load", buildChains);
    var rt;
    window.addEventListener("resize", function () {
      clearTimeout(rt);
      rt = setTimeout(buildChains, 200);
    });
  }

  // E-Mail-Adresse kopieren (kein Formular, keine Datenerhebung)
  var copyBtn = document.getElementById("copyMail");
  var status = document.getElementById("copyStatus");
  if (copyBtn) {
    copyBtn.addEventListener("click", function () {
      var mail = copyBtn.getAttribute("data-mail") || "";
      var done = function (ok) {
        if (!status) return;
        status.textContent = ok ? "Kopiert." : "Bitte manuell kopieren.";
        setTimeout(function () { status.textContent = ""; }, 2500);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(mail).then(function () { done(true); },
                                                  function () { done(false); });
      } else {
        done(false);
      }
    });
  }

  // Socials: Profil-Screenshot als Vorschau (Lightbox)
  var lb = document.getElementById("lb");
  if (lb) {
    var lbImg = document.getElementById("lbImg");
    var lbTitle = document.getElementById("lbTitle");
    var lbGo = document.getElementById("lbGo");
    var lastFocus = null;

    var openLb = function (btn) {
      lastFocus = btn;
      lbImg.setAttribute("src", btn.getAttribute("data-shot") || "");
      lbImg.setAttribute("alt", btn.getAttribute("data-alt") || "");
      var cap = btn.querySelector(".proof__cap");
      lbTitle.textContent = btn.getAttribute("data-title") || (cap ? cap.textContent : "Profil");
      var url = btn.getAttribute("data-url");
      lbGo.hidden = !url;
      lbGo.setAttribute("href", url || "#");
      lb.hidden = false;
      document.body.style.overflow = "hidden";
      var c = lb.querySelector(".lb__close");
      if (c) c.focus();
    };

    var closeLb = function () {
      if (lb.hidden) return;
      lb.hidden = true;
      lbImg.setAttribute("src", "");
      document.body.style.overflow = "";
      if (lastFocus) lastFocus.focus();
    };

    Array.prototype.forEach.call(document.querySelectorAll("[data-shot]"), function (btn) {
      btn.addEventListener("click", function () { openLb(btn); });
    });
    Array.prototype.forEach.call(lb.querySelectorAll("[data-close]"), function (el) {
      el.addEventListener("click", closeLb);
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" || e.key === "Esc") closeLb();
    });
  }
})();
