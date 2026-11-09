(function () {
  "use strict";

  var D = window.HANDBOOK;
  if (!D) {
    document.getElementById("app").innerHTML =
      '<p style="padding:40px;color:#9c9ca2">data.js 未加载。</p>';
    return;
  }

  var esc = function (s) {
    return String(s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  };

  var num = function (n) {
    return typeof n === "number" ? (Number.isInteger(n) ? String(n) : n.toFixed(1)) : esc(n);
  };

  var num1 = function (n) {
    return typeof n === "number" ? n.toFixed(1) : esc(n);
  };

  var badge = function (status) {
    var s = String(status);
    var cls = s === "已定" ? "ok" : s === "提案" ? "wip" : s === "待定" ? "todo" : "mixed";
    return '<span class="badge ' + cls + '">' + esc(s) + "</span>";
  };

  var rowChip = function (row) {
    var cls = "either";
    if (row.indexOf("前排") === 0) cls = "front";
    else if (row.indexOf("后排") === 0) cls = "back";
    return '<span class="chip ' + cls + '">' + esc(row) + "</span>";
  };

  var searchKey = function (parts) {
    return parts.filter(Boolean).join(" ").toLowerCase();
  };

  // ── 兵种 ──────────────────────────────
  function renderUnits() {
    var cards = D.units.map(function (u) {
      return (
        '<article class="card" data-search="' +
        esc(searchKey([u.name, u.source, u.row, u.sig, u.text, u.note, "兵种 一阶"])) +
        '">' +
          '<div class="card-head">' +
            "<h3>" + esc(u.name) + "</h3>" +
            '<span class="spacer"></span>' +
            badge(u.status) +
          "</div>" +
          '<div class="subline">' +
            '<span class="chip">' + esc(u.source) + "</span>" +
            rowChip(u.row) +
            "<span>一阶</span>" +
          "</div>" +
          '<dl class="stats">' +
            "<div><dt>成本</dt><dd>" + num(u.cost) + "<small>食</small></dd></div>" +
            "<div><dt>补给</dt><dd>" + num(u.supply) + "</dd></div>" +
            "<div><dt>生命</dt><dd>" + num1(u.hp) + "</dd></div>" +
            "<div><dt>攻击</dt><dd>" + num1(u.atk) + "</dd></div>" +
          "</dl>" +
          '<div class="signature"><span class="sig-name">' + esc(u.sig) +
            '</span><span class="sig-text">' + esc(u.text) + "</span></div>" +
          (u.note ? '<p class="note">' + esc(u.note) + "</p>" : "") +
        "</article>"
      );
    }).join("");

    var ok = D.units.filter(function (u) { return u.status === "已定"; }).length;
    var wip = D.units.length - ok;

    return (
      '<section class="sec" id="units" data-sec>' +
        '<div class="sec-head">' +
          "<h2>兵种</h2>" +
          "<p>一阶 12 个：共享 8 + 廪实专属 4。二 / 三阶未设计。战斗内所有单位基础 1 行动点，战后 HP 回满。</p>" +
          '<div class="counts">' +
            '<span class="count-pill">共 <b>' + D.units.length + "</b> 个</span>" +
            '<span class="count-pill">已定 <b>' + ok + "</b></span>" +
            '<span class="count-pill">提案 <b>' + wip + "</b></span>" +
          "</div>" +
        "</div>" +
        '<div class="grid units">' + cards + "</div>" +
      "</section>"
    );
  }

  // ── 敌人 ──────────────────────────────
  function renderEnemies() {
    var cards = D.enemies.map(function (e) {
      return (
        '<article class="card" data-search="' +
        esc(searchKey([e.name, e.family, e.row, e.sig, e.text, e.note, e.elite ? "强敌" : "敌人"])) +
        '">' +
          '<div class="card-head">' +
            "<h3>" + esc(e.name) + "</h3>" +
            (e.elite ? '<span class="chip elite">强敌</span>' : "") +
            '<span class="spacer"></span>' +
            badge(e.status) +
          "</div>" +
          '<div class="subline">' +
            '<span class="chip family">' + esc(e.family) + "</span>" +
            rowChip(e.row) +
            "<span>一阶</span>" +
          "</div>" +
          '<dl class="stats">' +
            "<div><dt>生命</dt><dd>" + num1(e.hp) + "</dd></div>" +
            "<div><dt>攻击</dt><dd>" + num1(e.atk) + "</dd></div>" +
            "<div><dt>行动点</dt><dd>1</dd></div>" +
            "<div><dt>阶级</dt><dd>一阶</dd></div>" +
          "</dl>" +
          '<div class="signature"><span class="sig-name">' + esc(e.sig) +
            '</span><span class="sig-text">' + esc(e.text) + "</span></div>" +
          (e.note ? '<p class="note">' + esc(e.note) + "</p>" : "") +
        "</article>"
      );
    }).join("");

    return (
      '<section class="sec" id="enemies" data-sec>' +
        '<div class="sec-head">' +
          "<h2>敌人</h2>" +
          "<p>与玩家兵种完全对称：同样使用 HP / 攻击 / 行动点 / 护盾 / 状态，没有第二套战斗逻辑。按族群分类，强敌 = 数值更高 + 独特机制。</p>" +
          '<div class="counts">' +
            '<span class="count-pill">共 <b>' + D.enemies.length + "</b> 个</span>" +
            '<span class="count-pill">强敌 <b>' + D.enemies.filter(function (e) { return e.elite; }).length + "</b></span>" +
          "</div>" +
        "</div>" +
        '<div class="grid enemies">' + cards + "</div>" +
      "</section>"
    );
  }

  // ── 虫种 ──────────────────────────────
  function renderSpecies() {
    var cards = D.species.map(function (s) {
      var actives = s.actives.map(function (a) {
        return (
          '<div class="active-row">' +
            '<span class="an">' + esc(a.name) + "</span>" +
            '<span class="cd">CD ' + a.cd + "</span>" +
            "<span>" + esc(a.text) + "</span>" +
          "</div>"
        );
      }).join("");

      var builds = s.builds.map(function (b) {
        return "<li>" + esc(b) + "</li>";
      }).join("");

      return (
        '<article class="card species-card" data-search="' +
        esc(searchKey([s.name, s.theme, s.passive, s.actives.map(function (a) { return a.name + a.text; }).join(" "), s.builds.join(" "), s.extra, "虫种 种族"])) +
        '">' +
          '<div class="card-head"><h3>' + esc(s.name) + "</h3>" +
            '<span class="spacer"></span>' + badge(s.status) + "</div>" +
          '<p class="theme">' + esc(s.theme) + "</p>" +
          '<div class="block"><h4>被动</h4><div class="passive">' + esc(s.passive) + "</div></div>" +
          '<div class="block"><h4>主动技能</h4><div class="actives">' + actives + "</div></div>" +
          '<div class="block"><h4>三条流派</h4><ul class="builds">' + builds + "</ul></div>" +
          '<p class="meta-line">' + esc(s.extra) + "</p>" +
        "</article>"
      );
    }).join("");

    return (
      '<section class="sec" id="species" data-sec>' +
        '<div class="sec-head">' +
          "<h2>虫种</h2>" +
          "<p>虫种决定被动、两个主动技能与专属兵种池。本期只做廪实。</p>" +
          '<div class="counts"><span class="count-pill">共 <b>' + D.species.length + "</b> 个</span></div>" +
        "</div>" +
        '<div class="grid">' + cards + "</div>" +
      "</section>"
    );
  }

  // ── 虫珀 ──────────────────────────────
  function renderRelics() {
    var R = D.relics;

    var types = R.types.map(function (t) {
      return (
        '<div class="relic-type" data-search="' + esc(searchKey(["虫珀", t.name, t.eg])) + '">' +
          "<h3>" + esc(t.name) + "</h3><p>" + esc(t.eg) + "</p></div>"
      );
    }).join("");

    var rarities = R.rarities.map(function (r) {
      return '<span class="chip">' + esc(r) + "</span>";
    }).join("");

    var entries = R.entries.length
      ? '<div class="grid">' + R.entries.map(function (e) {
          return '<article class="card" data-search="' + esc(searchKey([e.name, e.text, e.rarity])) + '">' +
            '<div class="card-head"><h3>' + esc(e.name) + '</h3><span class="spacer"></span>' +
            '<span class="chip">' + esc(e.rarity) + "</span></div>" +
            '<p class="note">' + esc(e.text) + "</p></article>";
        }).join("") + "</div>"
      : '<div class="callout">具体虫珀条目<b>尚未设计</b>。' +
        (R.status ? "当前状态：" + esc(R.status) + "。" : "") + "</div>";

    return (
      '<section class="sec" id="relics" data-sec>' +
        '<div class="sec-head">' +
          "<h2>虫珀</h2>" +
          "<p>正式名「虫珀」。来源：遗迹基础奖励、击败势力、中立交易、探索、事件。诅咒虫珀按负面强度独立分级。</p>" +
          '<div class="counts"><span class="count-pill">条目 <b>' + R.entries.length + "</b></span></div>" +
        "</div>" +
        entries +
        '<div class="block"><h4>效果类型</h4><div class="grid relic-types">' + types + "</div></div>" +
        '<div class="rarity-row"><span class="label">稀有度</span>' + rarities + "</div>" +
        (R.note ? '<p class="meta-line">' + esc(R.note) + "</p>" : "") +
      "</section>"
    );
  }

  // ── 势力 ──────────────────────────────
  function renderFactions() {
    var cards = D.factions.map(function (f) {
      return (
        '<article class="card faction-card" data-search="' +
        esc(searchKey([f.name, f.attitude, f.risk, f.reward, "势力"])) +
        '">' +
          '<div class="card-head"><h3>' + esc(f.name) + "</h3>" +
            '<span class="spacer"></span>' + badge(f.status) + "</div>" +
          '<div class="faction-attr"><span>态度 <b>' + esc(f.attitude) + "</b></span>" +
            "<span>风险 <b>" + esc(f.risk) + "</b></span></div>" +
          '<p class="note">回报：' + esc(f.reward) + "</p>" +
        "</article>"
      );
    }).join("");

    return (
      '<section class="sec" id="factions" data-sec>' +
        '<div class="sec-head">' +
          "<h2>势力</h2>" +
          "<p>每回合的每个事件组至少包含 1 个敌对事件。春季敌对更强。</p>" +
          '<div class="counts"><span class="count-pill">共 <b>' + D.factions.length + "</b> 类</span></div>" +
        "</div>" +
        '<div class="grid factions">' + cards + "</div>" +
      "</section>"
    );
  }

  // ── 事件 ──────────────────────────────
  function renderEvents() {
    var order = ["普通敌对", "强大敌对", "探索", "意外随机", "招募", "神秘遗迹"];

    var groups = order.map(function (cat) {
      var list = D.events.filter(function (e) { return e.cat === cat; });
      if (!list.length) return "";
      var rows = list.map(function (e) {
        return (
          '<div class="event-row" data-search="' +
          esc(searchKey([e.name, e.cat, e.opts, "事件"])) + '">' +
            '<span class="en">' + esc(e.name) + "</span>" +
            '<span class="eo">' + esc(e.opts) + "</span>" +
            badge(e.status) +
          "</div>"
        );
      }).join("");

      return (
        '<div class="group" data-group>' +
          '<h3 class="group-title">' + esc(cat) + " · " + list.length + "</h3>" +
          rows +
        "</div>"
      );
    }).join("");

    return (
      '<section class="sec" id="events" data-sec>' +
        '<div class="sec-head">' +
          "<h2>事件</h2>" +
          "<p>春季最小可玩集 13 个。每回合 3 组，每组 A→B→C→D 四个事件。除敌对 / 遗迹外，以下条目均为提案。</p>" +
          '<div class="counts"><span class="count-pill">共 <b>' + D.events.length + "</b> 个</span>" +
            '<span class="count-pill">全部为 <b>提案</b></span></div>' +
        "</div>" +
        groups +
      "</section>"
    );
  }

  // ── 枚举 ──────────────────────────────
  function renderEnums() {
    var cards = D.enums.map(function (g) {
      var items = g.items.map(function (it) {
        return (
          '<div class="enum-item">' +
            '<span class="k">' + esc(it.key) + "</span>" +
            '<span class="v">' + esc(it.value) + "</span>" +
            badge(it.status) +
          "</div>"
        );
      }).join("");

      return (
        '<article class="card enum-card" data-search="' +
        esc(searchKey([g.group].concat(g.items.map(function (i) { return i.key + " " + i.value; })))) +
        '">' +
          "<h3>" + esc(g.group) + "</h3>" + items +
        "</article>"
      );
    }).join("");

    return (
      '<section class="sec" id="enums" data-sec>' +
        '<div class="sec-head">' +
          "<h2>枚举值</h2>" +
          "<p>游戏里会出现的固定取值。数据契约要求 JSON 使用这些原值，不得改字。</p>" +
          '<div class="counts"><span class="count-pill">共 <b>' + D.enums.length + "</b> 组</span></div>" +
        "</div>" +
        '<div class="grid enums">' + cards + "</div>" +
      "</section>"
    );
  }

  // ── 数值 ──────────────────────────────
  function renderFormulas() {
    var rows = D.formulas.map(function (f) {
      return (
        '<div class="formula-row" data-search="' + esc(searchKey([f.name, f.formula, "数值 公式"])) + '">' +
          '<span class="fn">' + esc(f.name) + "</span>" +
          '<span class="ff">' + esc(f.formula) + "</span>" +
          badge(f.status) +
        "</div>"
      );
    }).join("");

    return (
      '<section class="sec" id="numbers" data-sec>' +
        '<div class="sec-head">' +
          "<h2>核心数值</h2>" +
          "<p>战斗结算只改「攻击值 → 伤害 → 护盾 → HP」四个环节，没有隐藏的减伤层。</p>" +
        "</div>" +
        '<div class="formula-table">' + rows + "</div>" +
      "</section>"
    );
  }

  // ── 分页定义 ──────────────────────────
  var PAGES = [
    { id: "units", title: "兵种", count: D.units.length },
    { id: "enemies", title: "敌人", count: D.enemies.length },
    { id: "species", title: "虫种", count: D.species.length },
    { id: "relics", title: "虫珀", count: D.relics.entries.length },
    { id: "factions", title: "势力", count: D.factions.length },
    { id: "events", title: "事件", count: D.events.length },
    { id: "enums", title: "枚举", count: D.enums.length },
    { id: "numbers", title: "数值", count: D.formulas.length }
  ];

  var PAGE_IDS = PAGES.map(function (p) { return p.id; });

  // ── 组装 ──────────────────────────────
  document.getElementById("app").innerHTML =
    renderUnits() +
    renderEnemies() +
    renderSpecies() +
    renderRelics() +
    renderFactions() +
    renderEvents() +
    renderEnums() +
    renderFormulas() +
    '<div class="empty hidden" id="empty"></div>' +
    '<nav class="pager" id="pager" aria-label="分页">' +
      '<button class="pg-arrow" id="pg-prev" type="button">← 上一页</button>' +
      '<div class="pg-nums" id="pg-nums"></div>' +
      '<button class="pg-arrow" id="pg-next" type="button">下一页 →</button>' +
      '<span class="pg-status" id="pg-status"></span>' +
    "</nav>";

  // 页头
  document.getElementById("title").innerHTML =
    esc(D.meta.title).replace("设计手册", '<span class="accent">设计手册</span>');
  document.getElementById("subtitle").textContent = D.meta.subtitle;
  document.getElementById("updated").innerHTML =
    "更新于 <b>" + esc(D.meta.updated) + "</b>";

  // 图例
  document.getElementById("legend").innerHTML = D.meta.legend.map(function (l) {
    return '<span class="item"><span class="badge ' + l.cls + '">' + esc(l.label) +
      "</span><span>" + esc(l.note) + "</span></span>";
  }).join("");

  // 顶部标签
  document.getElementById("tabs").innerHTML = PAGES.map(function (p, i) {
    return '<a href="#' + p.id + '" data-id="' + p.id + '">' + esc(p.title) +
      '<span class="n">' + p.count + "</span></a>";
  }).join("");

  // 底部页码
  document.getElementById("pg-nums").innerHTML = PAGES.map(function (p, i) {
    return '<button class="pg-num" type="button" data-id="' + p.id + '">' + (i + 1) + "</button>";
  }).join("");

  var sections = Array.prototype.slice.call(document.querySelectorAll("[data-sec]"));
  var tabEls = Array.prototype.slice.call(document.querySelectorAll(".tabs a"));
  var numEls = Array.prototype.slice.call(document.querySelectorAll(".pg-num"));
  var prevBtn = document.getElementById("pg-prev");
  var nextBtn = document.getElementById("pg-next");
  var statusEl = document.getElementById("pg-status");
  var emptyEl = document.getElementById("empty");
  var search = document.getElementById("search");
  var items = Array.prototype.slice.call(document.querySelectorAll("[data-search]"));
  var groups = Array.prototype.slice.call(document.querySelectorAll("[data-group]"));

  var currentId = PAGE_IDS[0];
  var maxOnPage = {}; // 每页可显示条目数，搜索时用于判断空页

  // ── 翻页 ──────────────────────────────
  function idFromHash() {
    var id = window.location.hash.slice(1);
    return PAGE_IDS.indexOf(id) === -1 ? PAGE_IDS[0] : id;
  }

  function pageCount(id) {
    var sec = document.getElementById(id);
    return sec ? sec.querySelectorAll("[data-search]:not(.hidden)").length : 0;
  }

  function showPage(id, opts) {
    opts = opts || {};
    if (PAGE_IDS.indexOf(id) === -1) id = PAGE_IDS[0];
    currentId = id;
    var idx = PAGE_IDS.indexOf(id);

    sections.forEach(function (s) {
      s.classList.toggle("active", s.id === id);
    });
    tabEls.forEach(function (a) {
      a.classList.toggle("active", a.getAttribute("data-id") === id);
    });
    numEls.forEach(function (b) {
      b.classList.toggle("active", b.getAttribute("data-id") === id);
    });

    prevBtn.disabled = idx === 0;
    nextBtn.disabled = idx === PAGE_IDS.length - 1;
    statusEl.textContent = (idx + 1) + " / " + PAGE_IDS.length;

    if (opts.scroll !== false) window.scrollTo(0, 0);
    if (opts.push) window.history.pushState(null, "", "#" + id);
  }

  function go(step) {
    var idx = PAGE_IDS.indexOf(currentId) + step;
    if (idx < 0 || idx >= PAGE_IDS.length) return;
    showPage(PAGE_IDS[idx], { push: true });
  }

  prevBtn.addEventListener("click", function () { go(-1); });
  nextBtn.addEventListener("click", function () { go(1); });

  tabEls.forEach(function (a) {
    a.addEventListener("click", function (e) {
      e.preventDefault();
      showPage(a.getAttribute("data-id"), { push: true });
    });
  });

  numEls.forEach(function (b) {
    b.addEventListener("click", function () {
      showPage(b.getAttribute("data-id"), { push: true });
    });
  });

  window.addEventListener("popstate", function () {
    showPage(idFromHash(), { scroll: false });
  });

  document.addEventListener("keydown", function (e) {
    var tag = (e.target && e.target.tagName) || "";
    if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return;
    if (e.key === "ArrowLeft") { go(-1); }
    else if (e.key === "ArrowRight") { go(1); }
  });

  // ── 搜索 ──────────────────────────────
  function refreshCounts() {
    var q = search.value.trim().toLowerCase();
    var total = 0;

    PAGES.forEach(function (p) {
      var n = q ? pageCount(p.id) : p.count;
      if (q) total += n;
      var a = tabEls.filter(function (el) { return el.getAttribute("data-id") === p.id; })[0];
      if (a) {
        a.querySelector(".n").textContent = n;
        a.classList.toggle("zero", !!q && n === 0);
      }
    });

    if (q && total === 0) {
      emptyEl.textContent = "没有匹配「" + search.value.trim() + "」的条目";
      emptyEl.classList.remove("hidden");
    } else {
      emptyEl.classList.add("hidden");
    }

    return total;
  }

  search.addEventListener("input", function () {
    var q = search.value.trim().toLowerCase();

    items.forEach(function (el) {
      el.classList.toggle("hidden", !!q && el.getAttribute("data-search").indexOf(q) === -1);
    });

    groups.forEach(function (g) {
      g.classList.toggle("hidden", !g.querySelector("[data-search]:not(.hidden)"));
    });

    var total = refreshCounts();

    // 当前页没有命中时，自动跳到第一个有命中的页
    if (q && total > 0 && pageCount(currentId) === 0) {
      var first = PAGES.filter(function (p) { return pageCount(p.id) > 0; })[0];
      if (first) showPage(first.id, { push: false });
    }
  });

  // ── 启动：默认第 1 页（兵种）──────────
  showPage(idFromHash(), { scroll: false });
})();
