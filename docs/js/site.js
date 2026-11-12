(function () {
  const lang = document.documentElement.lang === "es" ? "es" : "en";
  const copyLabel = lang === "es" ? "Copiar" : "Copy";
  const copiedLabel = lang === "es" ? "Copiado" : "Copied";
  const whereLabel = {
    workspace: lang === "es" ? "Terminal del workspace" : "Workspace terminal",
    guest: lang === "es" ? "Dentro del guest" : "Inside the guest",
    command: lang === "es" ? "Comando" : "Command"
  };

  document.querySelectorAll("pre").forEach(function (pre) {
    if (pre.closest(".codeblock")) {
      return;
    }
    const wrap = document.createElement("div");
    wrap.className = "codeblock";
    const bar = document.createElement("div");
    bar.className = "codeblock-bar";
    const loc = document.createElement("span");
    const place = pre.getAttribute("data-where");
    loc.textContent = whereLabel[place] || whereLabel.command;
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "codeblock-copy";
    btn.textContent = copyLabel;
    btn.addEventListener("click", function () {
      const text = pre.innerText;
      const done = function () {
        btn.textContent = copiedLabel;
        window.setTimeout(function () {
          btn.textContent = copyLabel;
        }, 1600);
      };
      const finish = function (ok) {
        if (ok) {
          done();
        }
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(function () {
          finish(true);
        }).catch(function () {
          finish(copyFallback(text));
        });
      } else {
        finish(copyFallback(text));
      }
    });
    bar.appendChild(loc);
    bar.appendChild(btn);
    pre.parentNode.insertBefore(wrap, pre);
    wrap.appendChild(bar);
    wrap.appendChild(pre);
  });

  function copyFallback(text) {
    const area = document.createElement("textarea");
    area.value = text;
    area.setAttribute("readonly", "");
    area.style.position = "fixed";
    area.style.left = "-9999px";
    document.body.appendChild(area);
    area.select();
    let ok = false;
    try {
      ok = document.execCommand("copy");
    } catch (err) {
      ok = false;
    }
    document.body.removeChild(area);
    return ok;
  }
})();
