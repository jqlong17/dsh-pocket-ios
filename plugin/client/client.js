window.__ModuleLoader__.load({
  id: "dsh-pocket-ios",
  factory: (require) => {
    var module = { exports: {} };
    var exports = module.exports;
    var React = require("react");

    var RELEASE_URL = "https://github.com/jqlong17/dsh-pocket-ios/releases/latest";
    var DOWNLOAD_URL = "https://github.com/jqlong17/dsh-pocket-ios/releases/latest/download/DSHPocket.ipa";
    var APP_STORE_URL = "https://apps.apple.com/app/id6832288744";
    var QR_SVG = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100%\" height=\"100%\" viewBox=\"0 0 37 37\" shape-rendering=\"crispEdges\"><path fill=\"#ffffff\" d=\"M0 0h37v37H0z\"/><path stroke=\"#000000\" d=\"M4 4.5h7m3 0h1m4 0h5m2 0h7M4 5.5h1m5 0h1m2 0h1m7 0h1m2 0h1m1 0h1m5 0h1M4 6.5h1m1 0h3m1 0h1m1 0h1m5 0h1m1 0h1m3 0h1m1 0h1m1 0h3m1 0h1M4 7.5h1m1 0h3m1 0h1m1 0h2m7 0h1m1 0h1m2 0h1m1 0h3m1 0h1M4 8.5h1m1 0h3m1 0h1m1 0h8m2 0h3m1 0h1m1 0h3m1 0h1M4 9.5h1m5 0h1m1 0h2m1 0h5m2 0h1m1 0h1m1 0h1m5 0h1M4 10.5h7m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h7M12 11.5h1m1 0h1m1 0h2m1 0h2m2 0h2M4 12.5h1m1 0h5m5 0h1m1 0h2m1 0h1m1 0h1m2 0h5M8 13.5h1m5 0h2m7 0h4m1 0h1m3 0h1M5 14.5h1m3 0h2m1 0h1m1 0h3m5 0h1m1 0h1m1 0h2M4 15.5h5m6 0h2m1 0h1m1 0h1m1 0h2m1 0h2m1 0h2m1 0h1M5 16.5h3m1 0h2m1 0h2m5 0h3m5 0h1m1 0h2M4 17.5h4m3 0h3m1 0h1m1 0h2m4 0h6m3 0h1M8 18.5h3m3 0h1m2 0h4m1 0h1m2 0h1m2 0h3M5 19.5h2m2 0h1m1 0h1m3 0h1m1 0h1m1 0h1m2 0h3m3 0h1m2 0h1M4 20.5h2m2 0h1m1 0h6m2 0h1m1 0h4m3 0h1m1 0h2M4 21.5h6m1 0h1m1 0h3m5 0h3m2 0h3m1 0h1m1 0h1M4 22.5h1m4 0h3m2 0h2m3 0h3m2 0h2m2 0h1m1 0h1M4 23.5h1m2 0h3m3 0h1m1 0h2m1 0h1m5 0h2m2 0h1m2 0h1M4 24.5h1m1 0h3m1 0h1m3 0h3m4 0h1m2 0h5m1 0h3M12 25.5h3m1 0h3m2 0h2m1 0h1m3 0h5M4 26.5h7m6 0h2m3 0h3m1 0h1m1 0h3M4 27.5h1m5 0h1m1 0h6m5 0h2m3 0h1M4 28.5h1m1 0h3m1 0h1m1 0h5m1 0h1m2 0h1m2 0h5m1 0h1m1 0h1M4 29.5h1m1 0h3m1 0h1m1 0h2m8 0h1m4 0h1m1 0h2M4 30.5h1m1 0h3m1 0h1m1 0h1m1 0h1m3 0h2m3 0h2m1 0h6M4 31.5h1m5 0h1m3 0h2m3 0h1m2 0h1m1 0h2m1 0h3m1 0h1M4 32.5h7m1 0h2m1 0h1m1 0h4m1 0h2m1 0h1m2 0h1m1 0h1\"/></svg>";
    var CARD_ID = "dsh-pocket-ios-card";

    function linkStyle(primary) {
      return {
        display: "inline-flex",
        alignItems: "center",
        gap: 6,
        padding: "7px 12px",
        borderRadius: 999,
        fontSize: 13,
        fontWeight: 600,
        textDecoration: "none",
        color: primary ? "#fff" : "#147A5E",
        background: primary ? "#147A5E" : "rgba(20,122,94,.08)",
        border: primary ? "1px solid #147A5E" : "1px solid rgba(20,122,94,.25)"
      };
    }

    function IOSCard() {
      return React.createElement(
        "div",
        { style: { display: "flex", flexWrap: "wrap", gap: 16, alignItems: "flex-start", padding: 16, borderRadius: 14, border: "1px solid rgba(0,0,0,.08)", background: "rgba(20,122,94,.04)", marginBottom: 18, boxSizing: "border-box", width: "100%", maxWidth: 620 } },
        React.createElement("div", {
          style: { width: 120, height: 120, flex: "0 0 120px", background: "#fff", borderRadius: 10, padding: 8, border: "1px solid rgba(0,0,0,.06)", boxSizing: "border-box" },
          dangerouslySetInnerHTML: { __html: QR_SVG }
        }),
        React.createElement(
          "div",
          { style: { flex: "1 1 220px", minWidth: 0 } },
          React.createElement("div", { style: { fontWeight: 600, fontSize: 15, marginBottom: 6 } }, "在 iPhone 上使用 DSH"),
          React.createElement(
            "div",
            { style: { fontSize: 13, opacity: 0.72, lineHeight: 1.6, marginBottom: 10 } },
            "用手机扫描二维码从 App Store 下载 DSH Pocket iOS；没有 App Store 的地区可从 GitHub Release 下载 IPA 自签安装。装好后在 App 里扫描电脑上 dsh-pocket 的二维码即可连接本机 DSH。"
          ),
          React.createElement(
            "div",
            { style: { display: "flex", gap: 10, flexWrap: "wrap" } },
            React.createElement("a", { href: APP_STORE_URL, target: "_blank", rel: "noreferrer", style: linkStyle(true) }, "在 App Store 下载"),
            React.createElement("a", { href: RELEASE_URL, target: "_blank", rel: "noreferrer", style: linkStyle(false) }, "GitHub Release（自签）"),
            React.createElement("a", { href: DOWNLOAD_URL, target: "_blank", rel: "noreferrer", style: linkStyle(false) }, "直接下载 IPA")
          )
        )
      );
    }

    var CARD_HTML =
      '<div style="box-sizing:border-box;width:100%;max-width:620px;display:flex;flex-wrap:wrap;gap:16px;align-items:flex-start;padding:16px;border-radius:14px;border:1px solid rgba(0,0,0,.08);background:rgba(20,122,94,.04);margin:0 0 16px 0;text-align:left">' +
        '<div style="box-sizing:border-box;width:110px;height:110px;flex:0 0 110px;background:#fff;border-radius:10px;padding:6px;border:1px solid rgba(0,0,0,.06)">' + QR_SVG + "</div>" +
        '<div style="flex:1 1 220px;min-width:0">' +
          '<div style="font-weight:600;font-size:15px;margin-bottom:6px">在 iPhone 上使用 DSH</div>' +
          '<div style="font-size:13px;opacity:.72;line-height:1.6;margin-bottom:10px">扫码从 App Store 下载 DSH Pocket iOS；没有 App Store 的地区可从 GitHub Release 下载 IPA 自签安装。装好后在 App 里扫描上方二维码连接本机 DSH。</div>' +
          '<div style="display:flex;gap:10px;flex-wrap:wrap">' +
            '<a href="' + APP_STORE_URL + '" target="_blank" rel="noreferrer" style="display:inline-flex;align-items:center;padding:7px 12px;border-radius:999px;font-size:13px;font-weight:600;text-decoration:none;color:#fff;background:#147A5E">在 App Store 下载</a>' +
            '<a href="' + RELEASE_URL + '" target="_blank" rel="noreferrer" style="display:inline-flex;align-items:center;padding:7px 12px;border-radius:999px;font-size:13px;font-weight:600;text-decoration:none;color:#147A5E;background:rgba(20,122,94,.08);border:1px solid rgba(20,122,94,.25)">GitHub Release（自签）</a>' +
            '<a href="' + DOWNLOAD_URL + '" target="_blank" rel="noreferrer" style="display:inline-flex;align-items:center;padding:7px 12px;border-radius:999px;font-size:13px;font-weight:600;text-decoration:none;color:#147A5E;background:rgba(20,122,94,.08);border:1px solid rgba(20,122,94,.25)">直接下载 IPA</a>' +
          "</div>" +
        "</div>" +
      "</div>";
    /** 尽力把卡片插到「手机访问 → 局域网访问」上方；失败时不影响原生设置入口。 */
    function insertCardInPocketPage() {
      if (typeof document === "undefined") return;
      if (document.getElementById(CARD_ID)) return;
      var nodes = Array.prototype.slice.call(document.querySelectorAll("div,span,p"));
      var label = null;
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i];
        if (el.childElementCount === 0 && (el.textContent || "").trim() === "局域网访问" && el.offsetParent !== null) { label = el; break; }
      }
      if (!label) return;
      // 从标签向上找「手机访问」页签的滚动内容容器；只在这里插入，避免落到设置弹窗的导航列里。
      var node = label.parentElement;
      var scroller = null;
      for (var depth = 0; depth < 8 && node && node !== document.body; depth++) {
        var style = window.getComputedStyle(node);
        var width = node.getBoundingClientRect().width;
        var scrollable = style.overflowY === "auto" || style.overflowY === "scroll";
        if (width >= 260 && scrollable) { scroller = node; break; }
        node = node.parentElement;
      }
      if (!scroller) return;
      var card = document.createElement("div");
      card.id = CARD_ID;
      card.innerHTML = CARD_HTML;
      scroller.insertBefore(card, scroller.firstChild);
    }

    var observer = null;
    function startObserver() {
      if (typeof document === "undefined" || typeof MutationObserver === "undefined" || observer) return;
      var run = function () { try { insertCardInPocketPage(); } catch (e) {} };
      observer = new MutationObserver(run);
      observer.observe(document.body, { childList: true, subtree: true });
      run();
    }

    function apply(ctx) {
      try {
        ctx.slots.inject("settings.section", function () {
          return ctx.slots.register(
            { name: "settings.section", id: "pocket-ios", order: 0, label: function () { return "iOS 客户端"; } },
            IOSCard
          );
        });
      } catch (e) {}
      startObserver();
    }

    module.exports = { apply: apply };
    return module.exports;
  }
});
