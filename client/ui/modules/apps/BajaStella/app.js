'use strict';

// =========================================================================
// BajaStella — Stella III EVO Racing Instrument
// Faithful recreation of the Anube Sport Stella III EVO device
// used in SCORE Baja 1000 / NORRA Mexican 1000 races.
// =========================================================================

angular.module('beamng.apps').directive('bajastella', function () {

  var ASSETS = '/ui/modules/apps/BajaStella/assets/';

  // -----------------------------------------------------------------------
  // CSS — Device housing, LCD screen, LED matrix, buttons
  // -----------------------------------------------------------------------
  var CSS = '<style>' +

    /* === Reset & Frame (tuned + slightly larger) === */
    '#stella-dev,#stella-dev *{box-sizing:border-box;margin:0;padding:0;}' +
    '#stella-dev{' +
      'width:362px;height:240px;max-width:100%;max-height:100%;position:relative;overflow:hidden;' +
      'pointer-events:auto;z-index:100;' +
      'display:flex;flex-direction:column;cursor:move;padding:3px 3px 4px;' +
      'background:#2a2a32;' +
      'border-radius:12px;border:2px solid #5f5f68;' +
      'font-family:"Bahnschrift","Arial Narrow","Segoe UI",sans-serif;' +
      'user-select:none;-webkit-user-select:none;' +
      'box-shadow:inset 0 0 0 1px rgba(255,255,255,.14),inset 0 -3px 8px rgba(0,0,0,.72),0 10px 22px rgba(0,0,0,.58);' +
    '}' +
    '#stella-dev::before{content:"";position:absolute;inset:5px;border-radius:8px;pointer-events:none;' +
      'box-shadow:inset 0 0 0 1px rgba(255,255,255,.08);}' +
    '#stella-dev.st-off{opacity:0;pointer-events:none;}' +
    '#stella-dev.st-powered-off .st-lcd{background:#07080a!important;border-color:#1a1b20!important;}' +
    '#stella-dev.st-powered-off .st-lcd>*{visibility:hidden!important;}' +
    '#stella-dev.st-powered-off .st-lcd::before,#stella-dev.st-powered-off .st-lcd::after{opacity:0!important;}' +
    '#stella-dev.st-powered-off .st-led-d{background:#14151a!important;box-shadow:none!important;animation:none!important;opacity:.35;}' +
    '#stella-dev.st-powered-off .st-logo-img,#stella-dev.st-powered-off .st-rnum,#stella-dev.st-powered-off .st-led-num{opacity:.28;}' +
    '#stella-dev.st-powered-off .st-btn-row{box-shadow:none;}' +

    /* === Header === */
    '.st-hdr{height:33px;flex-shrink:0;display:grid;grid-template-columns:58px 1fr 58px;align-items:center;padding:0 8px;' +
      'background:linear-gradient(180deg,#26262d,#0f1015);border-bottom:1px solid rgba(255,255,255,.09);}' +
    '.st-hdr-left{width:1px;height:1px;}' +
    '.st-hdr-mid{display:flex;align-items:center;justify-content:center;min-width:0;}' +
    '.st-hdr-right{display:flex;align-items:center;justify-content:flex-end;}' +
    '.st-logo-img{height:18px;width:auto;display:block;image-rendering:crisp-edges;}' +
    '.st-logo-txt{color:#d8dbe6;font-size:10px;font-weight:700;letter-spacing:1px;}' +
    '.st-rnum{margin-left:0;color:#d7d8de;font-size:15px;font-weight:700;font-style:italic;letter-spacing:1px;opacity:.96;}' +

    /* === LCD === */
    '.st-lcd{height:130px;flex-shrink:0;margin:8px 12px 5px;border-radius:2px;position:relative;overflow:hidden;' +
      'background:linear-gradient(160deg,#d6ebff 0%,#c8e2f9 50%,#bbd7f0 100%);' +
      'padding:0 4px 5px !important;box-shadow:inset 0 2px 5px rgba(0,0,0,.25),0 0 0 1px rgba(0,0,0,.45);}' +
    '.st-lcd::before{content:"";position:absolute;inset:0;z-index:1;pointer-events:none;' +
      'background-image:linear-gradient(rgba(67,90,191,.2) 1px,transparent 1px),linear-gradient(90deg,rgba(67,90,191,.2) 1px,transparent 1px);' +
      'background-size:4px 4px;opacity:.48;}' +
    '.st-lcd::after{content:"";position:absolute;inset:0;z-index:1;pointer-events:none;box-shadow:inset 0 0 26px rgba(39,70,145,.22);}' +
    '.st-lcd>*{position:relative;z-index:2;}' +
    '.lc{color:#313f9f;font-weight:700;line-height:1;font-family:"Bahnschrift SemiCondensed","Arial Narrow","Segoe UI",sans-serif;}' +
    '.lc-dim{color:#4d5a8e;}' +
    '.lc-label{color:#55628f;font-weight:700;font-size:9px;letter-spacing:1px;text-transform:uppercase;font-family:"Bahnschrift","Segoe UI",sans-serif;}' +

    /* === Normal mode === */
    '.lcd-main{display:grid;grid-template-columns:1fr auto;column-gap:6px;height:100%;}' +
    '.lcd-left{display:flex;flex-direction:column;justify-content:flex-start;min-width:0;}' +
    '.lcd-hdg{font-size:90px;line-height:.79;letter-spacing:-4px;}' +
    '.lcd-hdg sup{font-size:44px;vertical-align:top;margin-left:1px;line-height:1;}' +
    '.lcd-wp{font-size:24px;line-height:.95;letter-spacing:.4px;margin-top:3px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:166px;}' +
    '.lcd-right{display:flex;flex-direction:column;align-items:flex-end;justify-content:flex-start;min-width:130px;}' +
    '.lcd-vcp-row{display:flex;align-items:flex-end;justify-content:flex-end;gap:4px;}' +
    '.lcd-km-lbl{padding-bottom:6px;}' +
    '.lcd-dist-vcp{font-size:72px;line-height:.79;letter-spacing:-3px;}' +
    '.lcd-odo-lbl{margin-top:2px;margin-bottom:1px;}' +
    '.lcd-total{font-size:72px;line-height:.79;letter-spacing:-3px;}' +
    '.lcd-track{position:absolute;left:51%;bottom:28px;transform:translateX(-50%);font-size:11px;color:#5a5d62;' +
      'letter-spacing:4px;font-weight:700;text-transform:uppercase;white-space:nowrap;max-width:138px;overflow:hidden;text-overflow:ellipsis;}' +

    /* === Approach & idle === */
    '.lcd-apr{display:flex;flex-direction:column;height:100%;}' +
    '.lcd-apr-top{display:flex;align-items:flex-start;gap:4px;flex:1;}' +
    '.lcd-compass{width:76px;height:76px;flex-shrink:0;}' +
    '.lcd-compass svg{width:100%;height:100%;}' +
    '.lcd-apr-mid{flex:1;display:flex;flex-direction:column;justify-content:center;gap:2px;}' +
    '.lcd-apr-wp{font-size:20px;line-height:1;}' +
    '.lcd-apr-wpkm{font-size:11px;}' +
    '.lcd-apr-right{display:flex;flex-direction:column;align-items:flex-end;}' +
    '.lcd-apr-dlbl{font-size:8px;}' +
    '.lcd-apr-dm{font-size:46px;line-height:.86;letter-spacing:-2px;}' +
    '.lcd-apr-bot{display:flex;justify-content:space-between;align-items:flex-end;margin-top:2px;}' +
    '.lcd-hdg-sm{font-size:25px;letter-spacing:-1px;}' +
    '.lcd-hdg-sm sup{font-size:12px;}' +
    '.lcd-idle{display:flex;flex-direction:column;align-items:center;justify-content:center;height:100%;gap:2px;}' +
    '.lcd-idle-lbl{font-size:9px;letter-spacing:2px;}' +
    '.lcd-idle-hdg{font-size:74px;line-height:.82;letter-spacing:-3px;}' +
    '.lcd-idle-hdg sup{font-size:31px;}' +
    '.lcd-idle-spd{font-size:40px;letter-spacing:-1px;}' +
    '.lcd-idle-unit{font-size:12px;margin-left:4px;}' +

    /* === Overlays === */
    '.lcd-caution{position:absolute;inset:0;z-index:10;pointer-events:none;background:rgba(212,170,18,.14);display:flex;align-items:center;justify-content:center;}' +
    '@keyframes stCaution{0%,100%{opacity:1}50%{opacity:.22}}' +
    '.lcd-caution-txt{font-size:18px;font-weight:800;color:#523d04;letter-spacing:4px;animation:stCaution 1s ease-in-out infinite;}' +
    '.lcd-flag-overlay{position:absolute;left:0;right:0;bottom:4px;z-index:10;display:flex;justify-content:center;pointer-events:none;}' +
    '.lcd-flag-pill{background:rgba(18,94,225,.2);border:1px solid rgba(18,94,225,.5);border-radius:3px;padding:1px 9px;}' +
    '.lcd-flag-txt{font-size:10px;letter-spacing:1px;}' +

    /* === Speed zone overlay === */
    '.lcd-sz-overlay{position:absolute;inset:0;z-index:9;pointer-events:none;display:flex;flex-direction:column;align-items:center;justify-content:center;transition:opacity .3s;}' +
    '.lcd-sz-overlay.sz-warn{background:rgba(212,170,18,.12);}' +
    '.lcd-sz-overlay.sz-exceed{background:rgba(210,30,20,.16);}' +
    '@keyframes szPulse{0%,100%{opacity:1}50%{opacity:.3}}' +
    '.lcd-sz-limit{font-size:36px;font-weight:800;color:#523d04;letter-spacing:2px;line-height:1;}' +
    '.lcd-sz-limit.sz-red{color:#8b1a12;}' +
    '.lcd-sz-label{font-size:10px;font-weight:700;color:#5a5024;letter-spacing:2px;text-transform:uppercase;}' +
    '.lcd-sz-label.sz-red{color:#8b1a12;animation:szPulse .6s ease-in-out infinite;}' +
    '.lcd-sz-unit{font-size:14px;font-weight:700;color:#6b6232;margin-left:2px;}' +
    '.lcd-sz-unit.sz-red{color:#8b1a12;}' +
    /* the three states he described: ahead flashes yellow, inside sits red, over flashes red */
    '.lcd-sz-overlay.sz-ahead{background:rgba(212,170,18,.10);}' +
    '.lcd-sz-limit.sz-yellow,.lcd-sz-unit.sz-yellow,.lcd-sz-label.sz-yellow{color:#8a6300;animation:szPulse .6s ease-in-out infinite;}' +
    '.lcd-sz-limit.sz-in,.lcd-sz-unit.sz-in,.lcd-sz-label.sz-in{color:#8b1a12;animation:none;}' +
    '.lcd-sz-limit.sz-red,.lcd-sz-unit.sz-red{animation:szPulse .6s ease-in-out infinite;}' +

    /* === Blue flag LCD overlay === */
    '.lcd-bf-overlay{position:absolute;inset:0;z-index:8;pointer-events:none;}' +
    '@keyframes bfBlue{0%,100%{opacity:.9;background:rgba(20,80,200,.32)}50%{opacity:.1;background:rgba(20,80,200,.04)}}' +
    '@keyframes bfYellow{0%,100%{background:rgba(212,170,18,.22)}50%{background:rgba(212,170,18,.04)}}' +
    '@keyframes bfGreen{0%,100%{opacity:.9;background:rgba(30,200,80,.28)}50%{opacity:.1;background:rgba(30,200,80,.04)}}' +
    '.lcd-bf-overlay.bf-incoming{animation:bfBlue .55s ease-in-out infinite;}' +
    '.lcd-bf-overlay.bf-requesting{animation:bfYellow .8s ease-in-out infinite;}' +
    '.lcd-bf-overlay.bf-acknowledged{background:rgba(20,80,200,.28)!important;animation:none!important;}' +
    '.lcd-bf-overlay.bf-acked{animation:bfGreen .5s ease-in-out infinite;}' +

    /* === Bottom strip === */
    '.st-bot{height:64px;flex-shrink:0;display:flex;align-items:center;gap:8px;padding:0 12px;}' +
    '.st-led-blk{flex:0 0 132px;height:46px;display:flex;align-items:center;}' +
    '.st-led-num{display:none;}' +
    '.st-led-mx{width:132px;height:46px;display:grid;grid-template-columns:repeat(10,1fr);grid-template-rows:repeat(5,1fr);gap:2px;' +
      'padding:3px;background:#15151b;border:1px solid #4a4a4e;border-radius:2px;box-shadow:inset 0 3px 8px rgba(0,0,0,.7);}' +
    '.st-led-d{border-radius:50%;opacity:.95;background:radial-gradient(circle at 50% 52%,#1d1e24 30%,#787469 33%,#262730 67%);}' +
    '.st-led-mx.l-green .st-led-d.st-led-on{background:radial-gradient(circle,#9dff95 20%,#20c53f 48%,#153b1d 70%);box-shadow:0 0 5px rgba(53,220,70,.55);}' +
    '.st-led-mx.l-yellow .st-led-d.st-led-on{background:radial-gradient(circle,#fff2a0 20%,#d4bb22 48%,#483f17 70%);box-shadow:0 0 5px rgba(220,190,35,.55);}' +
    '.st-led-mx.l-red .st-led-d.st-led-on{background:radial-gradient(circle,#ffb2ab 20%,#d33426 48%,#4b1d18 70%);box-shadow:0 0 5px rgba(230,70,56,.55);}' +
    '.st-led-mx.l-blue .st-led-d.st-led-on{background:radial-gradient(circle,#b5ddff 20%,#2e8fe2 48%,#17344c 70%);box-shadow:0 0 5px rgba(65,150,230,.55);}' +
    '@keyframes stFlash{0%,100%{opacity:1}50%{opacity:.1}}' +
    '.st-led-mx.l-flash .st-led-d.st-led-on{animation:stFlash .55s ease-in-out infinite;}' +
    '.st-btns{flex:1;display:flex;flex-direction:column;justify-content:flex-end;min-width:0;}' +
    '.st-btn-row{height:41px;display:flex;border-radius:10px;border:1px solid rgba(255,255,255,.1);box-shadow:0 0 16px rgba(0,174,255,.35),0 0 10px rgba(255,50,50,.24);overflow:visible;position:relative;}' +
    '.st-btn{border:none;border-radius:0;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:3px;' +
      'font-family:"Bahnschrift","Segoe UI",sans-serif;font-weight:700;color:#fff;transition:filter .1s,transform .08s;}' +
    '.st-btn:active{transform:scale(.98);filter:brightness(.9);}' +
    '.st-btn img{width:17px;height:17px;display:block;}' +
    '.st-btn-sos{flex:1;background:#d82118;border-radius:9px 0 0 9px;}' +
    '.st-btn-sos img{filter:brightness(0) invert(1);}' +
    '.st-btn-ok{flex:1;background:#1fa036;font-size:18px;line-height:1;}' +
    '.st-btn-flag{flex:1;background:#2a9fe5;border-left:1px solid rgba(0,0,0,.25);border-radius:0 9px 9px 0;}' +
    '.st-btn-flag img{filter:brightness(0) invert(1);}' +
    '@keyframes stFlagPulse{0%,100%{box-shadow:0 0 8px rgba(38,162,242,.35) inset}50%{box-shadow:0 0 18px rgba(38,162,242,.88) inset}}' +
    '.st-btn-flag.fl-active{animation:stFlagPulse .9s ease-in-out infinite;}' +
    '.st-sos-bar{height:16px;display:flex;justify-content:center;align-items:flex-end;padding-bottom:2px;}' +
    '.st-sos-lbl{font-size:9px;color:#f2f3f6;font-weight:700;letter-spacing:1px;position:relative;line-height:1;}' +
    '.st-sos-lbl::before{content:"";position:absolute;left:50%;transform:translateX(-50%);top:-7px;width:70px;height:2px;background:#932428;border-radius:2px;}' +

    /* === Tooltips === */
    '.st-btn[data-tip]{position:relative;overflow:visible;}' +
    '.st-btn[data-tip]::before{content:attr(data-tip);position:absolute;bottom:calc(100% + 8px);left:50%;' +
      'transform:translateX(-50%);background:rgba(20,20,26,.95);color:#e7e9ee;' +
      'font-size:10px;font-weight:600;padding:5px 10px;border-radius:5px;' +
      'white-space:nowrap;pointer-events:none;opacity:0;letter-spacing:.4px;' +
      'transition:opacity .15s ease;z-index:999;border:1px solid rgba(100,150,255,.35);' +
      'box-shadow:0 4px 12px rgba(0,0,0,.6),inset 0 1px 2px rgba(255,255,255,.08);}' +
    '.st-btn[data-tip]:hover::before{opacity:1;}' +

      /* === the look of the real device, from his photograph === */
    '#stella-dev{background:#0d0e11 repeating-linear-gradient(0deg,rgba(255,255,255,.018) 0 1px,transparent 1px 3px);' +
      'border:2px solid #4b4d56;border-radius:11px;' +
      'box-shadow:inset 0 0 0 1px rgba(255,255,255,.10),inset 0 -3px 8px rgba(0,0,0,.85),0 12px 24px rgba(0,0,0,.6);}' +
    '#stella-dev::before{box-shadow:inset 0 0 0 1px rgba(255,255,255,.06);}' +
    '#stella-dev .st-hdr{background:linear-gradient(180deg,#1a1b20,#0b0c0f);border-bottom:1px solid rgba(255,255,255,.07);}' +
    '#stella-dev .st-rnum{color:#c9cbd4;}' +
    /* the pale blue screen with the fine dot grid the photograph shows */
    '#stella-dev .st-lcd{background:linear-gradient(180deg,#d3dfec 0%,#c4d2e2 100%);border:1px solid #8b98aa;border-radius:3px;}' +
    '#stella-dev .st-lcd::before{background-image:radial-gradient(circle,rgba(28,46,105,.13) 0 .6px,transparent .75px);background-size:3px 3px;opacity:1;}' +
    '#stella-dev .st-lcd::after{box-shadow:inset 0 0 22px rgba(39,70,145,.18);}' +
    '#stella-dev .lcd-main,#stella-dev .lcd-apr,#stella-dev .lcd-idle{color:#1b2d6b;}' +
    '#stella-dev .lcd-hdg,#stella-dev .lcd-dist-vcp,#stella-dev .lcd-total,#stella-dev .lcd-wp,#stella-dev .lcd-apr-dm,#stella-dev .lcd-apr-wp{color:#1b2d6b;font-weight:700;}' +
    /* the big numbers are made of dots on the real thing */
    '#stella-dev .lcd-hdg,#stella-dev .lcd-dist-vcp,#stella-dev .lcd-total{' +
      '-webkit-mask-image:radial-gradient(circle,#000 58%,transparent 66%);-webkit-mask-size:3px 3px;-webkit-mask-repeat:repeat;}' +
    '#stella-dev .lc-label{color:#3f4f86;}' +
    /* the led block sits on black, with the little serial turned on its side */
    '#stella-dev .st-led-mx{background:#050507;padding:3px;border-radius:3px;box-sizing:border-box;}' +
    '#stella-dev .st-led-num{display:block;writing-mode:vertical-rl;transform:rotate(180deg);font-size:9px;font-style:italic;font-weight:700;letter-spacing:1px;color:#9a9ca6;margin-right:3px;}' +
    /* the three buttons, vivid, with the soft glow they throw on the case */
    '#stella-dev .st-btn-row{border:1px solid rgba(255,255,255,.12);border-radius:10px;' +
      'box-shadow:0 0 18px rgba(0,174,255,.38),0 0 14px rgba(255,40,40,.30),0 0 10px rgba(40,220,90,.18);}' +
    '#stella-dev .st-btn-row .st-btn-sos{background:linear-gradient(180deg,#f0322a,#c81a12);}' +
    '#stella-dev .st-btn-row .st-btn-ok{background:linear-gradient(180deg,#2fc24a,#178a2c);color:#fff;font-weight:700;}' +
    '#stella-dev .st-btn-row .st-btn-flag{background:linear-gradient(180deg,#3fb0f2,#1f86cc);}' +
    '#stella-dev .st-btn:hover{filter:brightness(1.08);}' +
    /* the bracket under all three, labelled SOS */
    '#stella-dev .st-sos-lbl{color:#e6e8ee;font-size:9px;letter-spacing:2px;}' +
    '#stella-dev .st-sos-lbl::before{width:200px;height:1px;background:#8a2a2e;top:-6px;}' +
    '</style>';

  // -----------------------------------------------------------------------
  // LED dot grid (10 cols × 5 rows = 50 dots)
  // -----------------------------------------------------------------------
  var dots = '';
  for (var i = 0; i < 50; i++) dots += '<div class="st-led-d" ng-class="ledDotClass(' + i + ')"></div>';

  // -----------------------------------------------------------------------
  // HTML Template
  // -----------------------------------------------------------------------
  var HTML =
    '<div id="stella-dev" ng-class="{\'st-off\': !visible, \'st-powered-off\': !powered}" ng-mousedown="dragStart($event)" style="width:362px;height:240px">' +

      /* Header */
      '<div class="st-hdr">' +
        '<div class="st-hdr-left"></div>' +
        '<div class="st-hdr-mid">' +
          '<img class="st-logo-img" src="' + ASSETS + 'stella_logo.png" alt="STELLA III EVO"' +
            ' onerror="this.style.display=\'none\';this.insertAdjacentHTML(\'afterend\',\'<span class=\\\'st-logo-txt\\\'>STELLA III EVO</span>\')">' +
        '</div>' +
        '<div class="st-hdr-right"><span class="st-rnum">{{raceNum}}</span></div>' +
      '</div>' +

      /* LCD Screen */
      '<div class="st-lcd">' +

        /* Caution overlay */
        '<div class="lcd-caution" ng-show="(isStopped || cautionAhead) && raceActive && !szActive">' +
          '<span class="lcd-caution-txt">\u26A0 {{cautionAhead ? tr("stella.caution.warn","WARN") : tr("stella.caution.stop","CAUTION")}}</span>' +
        '</div>' +

        /* Blue flag LCD background overlay */
        '<div class="lcd-bf-overlay" ng-show="flagState!==\'none\'" ' +
          'ng-class="{\'bf-incoming\': flagState===\'incoming\', \'bf-requesting\': flagState===\'requesting\', \'bf-acknowledged\': flagState===\'acknowledged\', \'bf-acked\': flagState===\'acked\'}">' +
        '</div>' +

        /* Speed zone overlay */
        '<div class="lcd-sz-overlay" ng-show="szActive || szWarning" ng-class="{\x27sz-ahead\x27: szWarning && !szActive, \x27sz-warn\x27: szActive && !szExceeding, \x27sz-exceed\x27: szExceeding}">' +
          '<div class="lcd-sz-label" ng-class="{\x27sz-red\x27: szExceeding, \x27sz-in\x27: szActive && !szExceeding, \x27sz-yellow\x27: szWarning && !szActive}">{{szExceeding ? tr("stella.speedZone.limit","\\u26A0 SPEED LIMIT") : (szActive ? tr("stella.speedZone.zone","SPEED ZONE") : tr("stella.speedZone.ahead","SPEED ZONE AHEAD"))}}</div>' +
          '<div class="lcd-sz-limit" ng-class="{\x27sz-red\x27: szExceeding, \x27sz-in\x27: szActive && !szExceeding, \x27sz-yellow\x27: szWarning && !szActive}">{{szLimitMph}}<span class="lcd-sz-unit" ng-class="{\x27sz-red\x27: szExceeding, \x27sz-in\x27: szActive && !szExceeding, \x27sz-yellow\x27: szWarning && !szActive}">mph</span></div>' +
          '<div class="lcd-sz-label" ng-show="szExceeding" ng-class="{\x27sz-red\x27: szExceeding}">{{tr("stella.speedZone.reduce","REDUCE SPEED")}}</div>' +
        '</div>' +

        /* Blue flag overlay */
        '<div class="lcd-flag-overlay" ng-show="flagState===\'incoming\' || flagState===\'delivered\' || flagState===\'requested\' || flagState===\'accepted\' || flagState===\'go\' || flagState===\'cancelled\'">' +
          '<div class="lcd-flag-pill"><span class="lcd-flag-txt lc">' +
            '{{ flagState===\'incoming\' ? tr("stella.flag.overtake","OVERTAKE") : (flagState===\'go\' || flagState===\'accepted\' ? tr("stella.flag.go","PASS") : (flagState===\'cancelled\' ? tr("stella.flag.none","NO PASS") : tr("stella.flag.asking","ASKING"))) }}' +
            ' <span ng-if="flagPlayer">\u2014 {{flagPlayer}}</span></span></div>' +
        '</div>' +

        /* Idle mode */
        '<div class="lcd-idle" ng-show="!raceActive">' +
          '<div class="lc lc-label lcd-idle-lbl">{{tr("stella.idle.ready","READY")}}</div>' +
          '<div class="lc lcd-idle-hdg">{{hdg}}<sup>\u00B0</sup></div>' +
          '<div class="lc lcd-idle-spd">{{spd}}<span class="lc-dim lcd-idle-unit">{{tr("stella.unit.mph","mph")}}</span></div>' +
        '</div>' +

        /* Normal race mode */
        '<div class="lcd-main" ng-show="raceActive && !approaching">' +
          '<div class="lcd-left">' +
            '<div class="lc lcd-hdg">{{hdg}}<sup>\u00B0</sup></div>' +
            '<div class="lc lcd-wp">{{wpLabel}}</div>' +
          '</div>' +
          '<div class="lcd-right">' +
            '<div class="lcd-vcp-row">' +
              '<span class="lc-label lcd-km-lbl">{{tr("stella.unit.km","km")}}</span>' +
              '<span class="lc lcd-dist-vcp">{{dVCP}}</span>' +
            '</div>' +
            '<div class="lc-label lcd-odo-lbl">{{tr("stella.unit.odoKm","odo km")}}</div>' +
            '<div class="lc lcd-total">{{tDist}}</div>' +
          '</div>' +
          '<div class="lcd-track" ng-show="trackLabel">{{trackLabel}}</div>' +
        '</div>' +

        /* Approach mode */
        '<div class="lcd-apr" ng-show="raceActive && approaching">' +
          '<div class="lcd-apr-top">' +
            '<div class="lcd-compass"><svg viewBox="0 0 100 100" id="st-compass"></svg></div>' +
            '<div class="lcd-apr-mid">' +
              '<div class="lc lcd-apr-wp">{{wpName}}</div>' +
              '<div class="lc-dim lcd-apr-wpkm">{{wpKm}} {{tr("stella.unit.km","km")}}</div>' +
            '</div>' +
            '<div class="lcd-apr-right">' +
              '<div class="lc-label lcd-apr-dlbl">{{tr("stella.unit.distM","dist m")}}</div>' +
              '<div class="lc lcd-apr-dm">{{dMeters}}</div>' +
            '</div>' +
          '</div>' +
          '<div class="lcd-apr-bot">' +
            '<span class="lc lcd-hdg-sm">{{hdg}}<sup>\u00B0</sup></span>' +
            '<span class="lc lcd-total">{{tDist}}</span>' +
          '</div>' +
        '</div>' +

      '</div>' +

      /* Bottom strip */
      '<div class="st-bot">' +
        '<div class="st-led-blk">' +
          '<div class="st-led-num">{{raceNum}}</div>' +
          '<div class="st-led-mx" ng-class="ledCls">' + dots + '</div>' +
        '</div>' +
        '<div class="st-btns">' +
          '<div class="st-btn-row">' +
            '<button class="st-btn st-btn-sos" ng-mousedown="pressSOSStart($event)" ng-mouseup="pressSOSCancel($event)" ng-mouseleave="pressSOSCancel($event)" ng-touchstart="pressSOSStart($event)" ng-touchend="pressSOSCancel($event)" data-tip="{{tr(\'stella.tip.assistance\',\'Mechanical assistance\')}}">' +
              '<img src="' + ASSETS + 'sos.svg" alt="">' +
            '</button>' +
            '<button class="st-btn st-btn-ok" ng-click="pressOK()" ng-mousedown="$event.stopPropagation()" data-tip="{{tr(\'stella.tip.confirm\',\'Confirm\')}}">OK</button>' +
            '<button class="st-btn st-btn-flag" ng-click="pressFlag()" ng-mousedown="$event.stopPropagation()" ng-class="{\'fl-active\': flagState!==\'none\'}" data-tip="{{tr(\'stella.tip.overtake\',\'Overtake\')}}">' +
              '<img src="' + ASSETS + 'blueflag.svg" alt="">' +
            '</button>' +
          '</div>' +
        '</div>' +
      '</div>' +

    '</div>';

  // =====================================================================
  // Directive definition
  // =====================================================================
  return {
    template: CSS + HTML,
    restrict: 'E',
    scope: true,
    controller: ['$scope', function ($scope) {

      // ---- State ----
      $scope.visible     = true;
      $scope.powered     = true;
      try {
        var savedPower = localStorage.getItem("rm.stella.powered");
        if (savedPower === "0") $scope.powered = false;
        if (savedPower === "1") $scope.powered = true;
      } catch (_) {}
      $scope.hdg         = '000';
      $scope.spd         = '0';
      $scope.dVCP        = '00.00';
      $scope.dMeters     = '0';
      $scope.wpName      = '';
      $scope.wpLabel     = 'VCP 0';
      $scope.wpKm        = '0.00';
      $scope.tDist       = '00.00';
      $scope.raceActive  = false;
      $scope.approaching = false;
      $scope.isStopped   = false;
      $scope.cautionAhead = false;
      $scope.breakdownActive = false;
      $scope.hazardAhead = false;
      $scope.flagState   = 'none';
      $scope.flagPlayer  = '';
      $scope.raceNum     = '0000';
      $scope.trackLabel  = '';
      $scope.ledCls      = '';
      $scope.ledPattern  = 'none';
      $scope._ledMask    = [];

      // Speed zone state
      $scope.szActive    = false;
      $scope.szWarning   = false;
      $scope.szExceeding = false;
      $scope.szLimit     = 0;
      $scope.szName      = '';
      $scope.szLimitMph  = 0;
      $scope.tr = function(key, fallback, vars) {
        if (window.BajaI18n && window.BajaI18n.t) return window.BajaI18n.t(key, vars, fallback);
        return fallback || key || '';
      };

      // ---- Helpers ----
      function pad(n, len) { var s = String(n); while (s.length < len) s = '0' + s; return s; }
      function fmtKm(km) {
        var w = Math.floor(km), f = Math.floor((km - w) * 100);
        return pad(w, 2) + '.' + pad(f, 2);
      }
      function lua(cmd) { if (typeof bngApi !== 'undefined') bngApi.engineLua(cmd); }

      // Two digits on ten by five dots, four wide each with a gap between.
      // Anything the dots cannot spell lights them all, as before.
      var DIGITS = {
        '0': ['1111', '1001', '1001', '1001', '1111'],
        '1': ['0010', '0110', '0010', '0010', '0111'],
        '2': ['1111', '0001', '1111', '1000', '1111'],
        '3': ['1111', '0001', '0111', '0001', '1111'],
        '4': ['1001', '1001', '1111', '0001', '0001'],
        '5': ['1111', '1000', '1111', '0001', '1111'],
        '6': ['1111', '1000', '1111', '1001', '1111'],
        '7': ['1111', '0001', '0010', '0100', '0100'],
        '8': ['1111', '1001', '1111', '1001', '1111'],
        '9': ['1111', '1001', '1111', '0001', '1111']
      };
      function digitRows(text) {
        var n = parseInt(text, 10);
        if (isNaN(n) || n < 0 || n > 99) {
          return ['1111111111', '1111111111', '1111111111', '1111111111', '1111111111'];
        }
        var s = String(n);
        var rows = [];
        for (var r = 0; r < 5; r++) {
          if (s.length === 1) {
            rows.push('000' + DIGITS[s][r] + '000');
          } else {
            rows.push(DIGITS[s.charAt(0)][r] + '00' + DIGITS[s.charAt(1)][r]);
          }
        }
        return rows;
      }

      function ledMask(pattern) {
        var p = pattern || 'none';
        var rows;
        if (p === 'triangle') {
          rows = ['0000010000', '0000111000', '0001111100', '0011111110', '0111111111'];
        } else if (p === 'lines') {
          rows = ['1100110011', '1100110011', '0000000000', '1100110011', '1100110011'];
        } else if (p === 'sos') {
          rows = ['1101110110', '1001010100', '1101010110', '0101010010', '1101110110'];
        } else if (p === 'none') {
          rows = ['0000000000', '0000000000', '0000000000', '0000000000', '0000000000'];
        } else if (p.indexOf('limit:') === 0) {
          rows = digitRows(p.slice(6));
        } else {
          rows = ['1111111111', '1111111111', '1111111111', '1111111111', '1111111111'];
        }

        var mask = [];
        for (var r = 0; r < rows.length; r++) {
          for (var c = 0; c < rows[r].length; c++) {
            mask.push(rows[r].charAt(c) === '1');
          }
        }
        while (mask.length < 50) mask.push(false);
        return mask;
      }

      function setLedVisual(color, flash, pattern) {
        var cls = '';
        if (color && color !== 'off') cls = 'l-' + color;
        if (flash) cls += ' l-flash';
        $scope.ledCls = cls;

        var p = pattern || (cls ? 'all' : 'none');
        if (!color || color === 'off') p = 'none';
        $scope.ledPattern = p;
        $scope._ledMask = ledMask(p);
      }

      $scope.ledDotClass = function (idx) {
        return ($scope._ledMask && $scope._ledMask[idx]) ? 'st-led-on' : '';
      };

      setLedVisual('off', false, 'none');

      // ---- Drag ----
      // Only move the Race Manager .rm-stella host. Never walk up to .rm-root
      // or the top bar. Clear bottom/right before setting top or the box collapses
      // (CSS had bottom:316px) and both Stella and nearby UI look "gone".
      $scope.dragStart = function (e) {
        if (e.button !== 0) return;
        var el = document.getElementById('stella-dev');
        if (!el) return;
        var wrap = el.closest ? el.closest('.rm-stella') : null;
        if (!wrap) {
          wrap = el.parentElement;
          while (wrap && wrap !== document.body) {
            if (wrap.classList && wrap.classList.contains('rm-stella')) break;
            if (wrap.classList && wrap.classList.contains('rm-root')) { wrap = null; break; }
            var pos = window.getComputedStyle(wrap).position;
            if (pos === 'absolute' || pos === 'fixed') break;
            wrap = wrap.parentElement;
          }
        }
        if (!wrap || wrap === document.body) return;
        if (wrap.classList && wrap.classList.contains('rm-root')) return;

        var r = wrap.getBoundingClientRect();
        var ox = e.clientX - r.left, oy = e.clientY - r.top;
        var EDGE = 12;

        function place(left, top) {
          var vw = window.innerWidth || 1280;
          var vh = window.innerHeight || 720;
          var w = wrap.offsetWidth || 362;
          var h = wrap.offsetHeight || 240;
          if (left < EDGE - w + 40) left = EDGE - w + 40;
          if (left > vw - 40) left = vw - 40;
          if (top < 0) top = 0;
          if (top > vh - 40) top = vh - 40;
          wrap.style.right = 'auto';
          wrap.style.bottom = 'auto';
          wrap.style.transform = 'none';
          wrap.style.left = left + 'px';
          wrap.style.top = top + 'px';
        }

        function onMove(ev) {
          place(ev.clientX - ox, ev.clientY - oy);
        }
        function onUp() {
          document.removeEventListener('mousemove', onMove);
          document.removeEventListener('mouseup', onUp);
          try {
            var root = document.querySelector('.rm-root');
            var host = root && root.parentElement;
            var hostW = host ? host.clientWidth : window.innerWidth;
            var hostH = host ? host.clientHeight : window.innerHeight;
            // Skip save while HUD editor has Race Manager in a partial box
            if (hostW < window.innerWidth * 0.85 || hostH < window.innerHeight * 0.85) return;
            localStorage.setItem('rm.panel.stella', JSON.stringify({
              x: wrap.offsetLeft, y: wrap.offsetTop
            }));
          } catch (_) {}
        }
        document.addEventListener('mousemove', onMove);
        document.addEventListener('mouseup', onUp);
        e.preventDefault();
        e.stopPropagation();
      };

      // ---- Init wrapper cleanup ----
      setTimeout(function() {
        if (window.BajaUI) BajaUI.setup('stella-dev');
        if (window.BajaI18n && window.BajaI18n.ensureNamespaces) {
          window.BajaI18n.ensureNamespaces(['stella']).then(function() {
            $scope.$applyAsync();
          });
        }
      }, 0);

      // ---- VCP checkpoint sound ----
      // ~55% quieter than the stored / default VCP volume.
      var STELLA_VOLUME_SCALE = 0.45;
      var stellaBaseVolume = 0.5;
      var vcpAudio = new Audio('/ui/modules/apps/BajaStella/vcp_sound.mp3');
      try {
        var sv = localStorage.getItem('bajaVcpVolume');
        if (sv !== null) stellaBaseVolume = parseInt(sv, 10) / 100;
      } catch (_) {}
      if (isNaN(stellaBaseVolume)) stellaBaseVolume = 0.5;

      function stellaVolume() {
        if (!$scope.powered) return 0;
        return Math.max(0, Math.min(1, stellaBaseVolume * STELLA_VOLUME_SCALE));
      }

      function applyStellaVolume() {
        var vol = stellaVolume();
        try { vcpAudio.volume = vol; } catch (_) {}
        if (szEntryAudio) try { szEntryAudio.volume = vol; } catch (_) {}
        if (szExceedAudio) try { szExceedAudio.volume = vol; } catch (_) {}
        if (overtakeAudio) try { overtakeAudio.volume = vol; } catch (_) {}
      }

      applyStellaVolume();

      function playVCPSound() {
        if (!$scope.powered) return;
        applyStellaVolume();
        try { vcpAudio.currentTime = 0; vcpAudio.play(); } catch (e) { /* user gesture guard */ }
      }

      // ---- Speed zone sounds ----
      // Sound files — user will place them in BajaStella/sounds/
      var SZ_SOUND_PATH = '/ui/modules/apps/BajaStella/sounds/';
      var szEntryAudio   = null;  // beeps repetidos al entrar a speed zone
      var szExceedAudio  = null;  // beep continuo al exceder limite
      var szStopped      = null;  // alerta vehiculo detenido
      var szOvertake     = null;  // beeps urgentes vehiculo detras
      var szSosAudio     = null;  // alerta critica SOS

      function initSZAudio(filename) {
        try {
          var a = new Audio(SZ_SOUND_PATH + filename);
          a.volume = stellaVolume();
          return a;
        } catch (_) { return null; }
      }

      // Lazy-init sounds (created on first use so missing files don't block load)
      function getSZEntryAudio() {
        if (!szEntryAudio) szEntryAudio = initSZAudio('speed_zone_entry.mp3');
        return szEntryAudio;
      }
      function getSZExceedAudio() {
        if (!szExceedAudio) szExceedAudio = initSZAudio('speed_zone_exceed.mp3');
        return szExceedAudio;
      }

      var _szExceedInterval = null;

      function playSZEntrySound() {
        if (!$scope.powered) return;
        var a = getSZEntryAudio();
        if (a) { try { a.volume = stellaVolume(); a.currentTime = 0; a.play(); } catch (_) {} }
      }

      function startSZExceedLoop() {
        stopSZExceedLoop();
        if (!$scope.powered) return;
        var a = getSZExceedAudio();
        if (!a) return;
        try { a.volume = stellaVolume(); a.currentTime = 0; a.loop = true; a.play(); } catch (_) {}
      }

      function stopSZExceedLoop() {
        var a = getSZExceedAudio();
        if (a) { try { a.pause(); a.currentTime = 0; a.loop = false; } catch (_) {} }
      }

      var overtakeAudio = null;
      function getOvertakeAudio() {
        if (!overtakeAudio) overtakeAudio = initSZAudio('beep_corto.mp3');
        return overtakeAudio;
      }
      function playOvertakeBeep(times) {
        if (!$scope.powered) return;
        var a = getOvertakeAudio();
        if (!a) return;
        try { a.volume = stellaVolume(); } catch (_) {}
        var count = 0;
        function next() {
          if (count >= times) { a.onended = null; return; }
          count++;
          try { a.currentTime = 0; a.play(); } catch (_) {}
        }
        a.onended = function () { setTimeout(next, 200); };
        next();
      }

      $scope.$on('BajaStella_VCPSound', playVCPSound);
      // Backward compat: old event from race.lua
      $scope.$on('BajaVCP_Sound', playVCPSound);
      // Volume change from BajaConfigs
      $scope.$on('BajaVCP_VolumeChange', function (_ev, vol) {
        stellaBaseVolume = Math.max(0, Math.min(1, vol));
        applyStellaVolume();
      });

      // ---- Compass SVG update ----
      function updateCompass(heading, bearing) {
        var svg = document.getElementById('st-compass');
        if (!svg) return;

        var rel = bearing - heading;
        while (rel >  180) rel -= 360;
        while (rel < -180) rel += 360;

        var cx = 50, cy = 55, r = 36;
        var sA = (-90) * Math.PI / 180;          // top = north
        var eA = (-90 + rel) * Math.PI / 180;

        var x1 = cx + r * Math.cos(sA), y1 = cy + r * Math.sin(sA);
        var x2 = cx + r * Math.cos(eA), y2 = cy + r * Math.sin(eA);
        var la = Math.abs(rel) > 180 ? 1 : 0;
        var sw = rel > 0 ? 1 : 0;

        // Arrow tip on the arc endpoint
        var ax1 = x2 + 6 * Math.cos(eA - 2.6), ay1 = y2 + 6 * Math.sin(eA - 2.6);
        var ax2 = x2 + 6 * Math.cos(eA + 2.6), ay2 = y2 + 6 * Math.sin(eA + 2.6);

        svg.innerHTML =
          // Outer circle
          '<circle cx="' + cx + '" cy="' + cy + '" r="42" fill="none" stroke="#3a5070" stroke-width="1.2" opacity="0.35"/>' +
          // Tick marks at N/E/S/W
          '<line x1="50" y1="11" x2="50" y2="16" stroke="#3a5070" stroke-width="1" opacity="0.5"/>' +
          '<line x1="50" y1="94" x2="50" y2="99" stroke="#3a5070" stroke-width="1" opacity="0.3"/>' +
          '<line x1="6" y1="55" x2="11" y2="55" stroke="#3a5070" stroke-width="1" opacity="0.3"/>' +
          '<line x1="89" y1="55" x2="94" y2="55" stroke="#3a5070" stroke-width="1" opacity="0.3"/>' +
          // Direction arc
          '<path d="M ' + x1 + ' ' + y1 + ' A ' + r + ' ' + r + ' 0 ' + la + ' ' + sw + ' ' + x2 + ' ' + y2 + '"' +
          ' fill="none" stroke="#1a2842" stroke-width="4.5" stroke-linecap="round"/>' +
          // Arrow tip
          '<polygon points="' + x2 + ',' + y2 + ' ' + ax1 + ',' + ay1 + ' ' + ax2 + ',' + ay2 + '" fill="#1a2842"/>' +
          // Center dot
          '<circle cx="' + cx + '" cy="' + cy + '" r="2.5" fill="#1a2842"/>';
      }

      // ---- Main data update (10 fps from Lua) ----
      $scope.$on('BajaStella_Update', function (_ev, d) {
        $scope.$applyAsync(function () {
          if (!d) return;
          $scope.hdg        = pad(d.heading || 0, 3);
          if ($scope._airKmh == null) $scope.spd = String(d.speed || 0);
          $scope.dVCP       = fmtKm(d.distToVCPkm || 0);
          $scope.dMeters    = String(d.distToVCPm || 0);
          $scope.wpName     = d.vcpName || 'VCP';
          $scope.wpLabel    = pad(d.vcpIndex || 0, 2) + '-' + (d.vcpName || 'WP');
          $scope.wpKm       = d.distToVCPkm != null ? d.distToVCPkm.toFixed(2) : '0.00';
          $scope.tDist      = fmtKm(d.totalDistKm || 0);
          $scope.raceActive = !!(d.raceActive);
          $scope.approaching = !!(d.isApproaching);
          $scope.isStopped  = !!(d.isStopped);
          $scope.cautionAhead = !!(d.cautionAhead || d.hazardAhead);
          $scope.breakdownActive = !!(d.breakdownActive);
          $scope.hazardAhead = !!(d.hazardAhead);
          $scope.flagState  = d.blueFlagState || 'none';
          $scope.flagPlayer = d.blueFlagPlayer || '';
          var pid = (d.playerId != null) ? Number(d.playerId) : NaN;
          $scope.raceNum    = isNaN(pid) ? pad(d.vcpIndex || 0, 4) : pad(Math.max(0, Math.floor(pid)), 4);
          $scope.trackLabel = d.trackName ? d.trackName.toUpperCase() : '';

          // Speed zone data from stella.lua
          $scope.szActive    = !!(d.speedZoneActive);
          $scope.szWarning   = !!(d.speedZoneWarning);
          $scope.szExceeding = !!(d.speedExceeding);
          $scope.szLimit     = d.speedZoneLimit || 0;
          $scope.szLimitMph  = d.speedZoneLimitMph || Math.round($scope.szLimit * 0.621371);
          $scope.szName      = d.speedZoneName || '';

          setLedVisual(d.ledColor, d.ledFlash, d.ledPattern);

          // Update compass SVG in approach mode
          if (d.isApproaching && d.bearingToVCP != null) {
            setTimeout(function () { updateCompass(d.heading || 0, d.bearingToVCP || 0); }, 0);
          }
        });
      });

      // ---- Show / Hide ----
      $scope.$on('BajaStella_Show', function () {
        $scope.$applyAsync(function () {
          $scope.visible = true;
          // Use refresh (not setup) so the idempotent _done guard is cleared and
          // pointer-events:auto is explicitly set inline AFTER st-off is removed.
          setTimeout(function() { if (window.BajaUI) BajaUI.refresh('stella-dev'); }, 0);
        });
      });
      $scope.$on('BajaStella_Hide', function () {
        $scope.$applyAsync(function () { $scope.visible = false; });
      });

      // ---- LED event ----
      $scope.$on('BajaStella_LED', function (_ev, d) {
        $scope.$applyAsync(function () {
          setLedVisual(d && d.color, d && d.flash, d && d.pattern);
        });
      });

      // ---- Blue flag event ----
      $scope.$on('BajaStella_BlueFlag', function (_ev, d) {
        $scope.$applyAsync(function () {
          var st = (d && d.state) || 'none';
          $scope.flagState  = (st === 'clear') ? 'none' : st;
          $scope.flagPlayer = (d && d.playerName) || '';
          if (st === 'incoming') { playOvertakeBeep(3); }
        });
      });

      // ---- VCP crossed (LED green driven by Lua via BajaStella_LED + BajaStella_Update) ----
      $scope.$on('BajaStella_VCPCrossed', function () { /* LED state managed by stella.lua */ });

      // ---- Speed zone events (sound triggers from stella.lua) ----
      $scope.$on('BajaStella_SpeedZone', function (_ev, d) {
        if (!d) return;
        if (d.event === 'enter' || d.event === 'advance') {
          playSZEntrySound();
        } else if (d.event === 'exceeded') {
          startSZExceedLoop();
        } else if (d.event === 'normalized') {
          stopSZExceedLoop();
        } else if (d.event === 'exit') {
          stopSZExceedLoop();
          playVCPSound();
        }
      });


      var streamsList = ['electrics'];
      if (typeof StreamsManager !== 'undefined' && StreamsManager.add) {
        try { StreamsManager.add(streamsList); } catch (_) {}
      }
      $scope.$on('$destroy', function () {
        if (typeof StreamsManager !== 'undefined' && StreamsManager.remove) {
          try { StreamsManager.remove(streamsList); } catch (_) {}
        }
      });
      $scope.$on('streamsUpdate', function (_ev, streams) {
        if (!streams || !streams.electrics) return;
        var e = streams.electrics;
        var ms = e.airspeed;
        if (ms == null || isNaN(ms)) ms = e.wheelspeed;
        if (ms == null || isNaN(ms)) return;
        var mph = Math.round(ms * 2.2369362920544);
        $scope._airKmh = mph;
        $scope.$applyAsync(function () { $scope.spd = String(mph); });
      });

      $scope.$on('BajaStella_AlertSound', function (_ev, d) {
        playOvertakeBeep((d && d.loud) ? 5 : 3);
      });
      $scope.$on('BajaStella_Proximity', function (_ev, d) {
        if (d && !d.clear) playOvertakeBeep(d.kind === 'rearApproach' ? 3 : 1);
      });
      $scope.$on('BajaStella_Breakdown', function (_ev, d) {
        $scope.$applyAsync(function () { $scope.breakdownActive = !!(d && d.active); });
      });
      $scope.$on('BajaStella_HazardAhead', function (_ev, d) {
        $scope.$applyAsync(function () {
          $scope.hazardAhead = !!(d && d.active !== false);
          if (d && d.active === false) $scope.hazardAhead = false;
          $scope.cautionAhead = $scope.hazardAhead;
        });
      });
      var comboPress = { sos: 0, ok: 0, flag: 0 };
      var COMBO_MS = 3000;

      function persistPower() {
        try { localStorage.setItem("rm.stella.powered", $scope.powered ? "1" : "0"); } catch (_) {}
      }

      function powerOff() {
        $scope.powered = false;
        persistPower();
        comboPress.sos = comboPress.ok = comboPress.flag = 0;
        stopSZExceedLoop();
        try { vcpAudio.pause(); vcpAudio.currentTime = 0; } catch (_) {}
        if (szEntryAudio) try { szEntryAudio.pause(); szEntryAudio.currentTime = 0; } catch (_) {}
        if (overtakeAudio) try { overtakeAudio.pause(); overtakeAudio.onended = null; } catch (_) {}
        applyStellaVolume();
      }

      function powerOn() {
        $scope.powered = true;
        persistPower();
        comboPress.sos = comboPress.ok = comboPress.flag = 0;
        applyStellaVolume();
      }

      // All three buttons pressed within 3 seconds powers off.
      // While off, any one button press powers back on and swallows the action.
      function noteButton(which) {
        if (!$scope.powered) {
          powerOn();
          return true;
        }
        var now = Date.now();
        comboPress[which] = now;
        if (comboPress.sos && comboPress.ok && comboPress.flag
            && (now - comboPress.sos) <= COMBO_MS
            && (now - comboPress.ok) <= COMBO_MS
            && (now - comboPress.flag) <= COMBO_MS) {
          powerOff();
          return true;
        }
        return false;
      }

      // A press, not a three second hold. The hold was the original
      // unit's and nobody knew it was there: the button was pressed and
      // nothing happened. Pressed again, the car is moving again.
      $scope.pressSOSStart = function (e) {
        if (e && e.stopPropagation) e.stopPropagation();
        if (noteButton('sos')) return;
        $scope.pressSOS();
      };
      $scope.pressSOSCancel = function (e) {
        if (e && e.stopPropagation) e.stopPropagation();
      };

      // ---- Button handlers ----
      $scope.pressSOS = function () {
        if (!$scope.powered) return;
        lua('if extensions.bajaStella then extensions.bajaStella.requestMechanicalBreakdown() elseif extensions.gameCommands then extensions.gameCommands.stellaSOS() end');
      };
      $scope.pressOK = function () {
        if (noteButton('ok')) return;
        lua('if extensions.bajaStella then extensions.bajaStella.acknowledgeBlueFlag() elseif extensions.gameCommands then extensions.gameCommands.stellaOK() end');
      };
      $scope.pressFlag = function () {
        if (noteButton('flag')) return;
        if ($scope.flagState === 'incoming') {
          lua('if extensions.bajaStella then extensions.bajaStella.acknowledgeBlueFlag() elseif extensions.gameCommands then extensions.gameCommands.stellaOK() end');
        } else {
          lua('if extensions.bajaStella then extensions.bajaStella.requestBlueFlag() elseif extensions.gameCommands then extensions.gameCommands.stellaFlag() end');
        }
      };


      // Keybinds from raceManager_keys (Controls → bind RM Stella *)
      function onStellaKey(data) {
        var action = (data && data.action) || "";
        $scope.$applyAsync(function () {
          if (action === "toggle") {
            if ($scope.powered) powerOff(); else powerOn();
            return;
          }
          if (action === "on") { powerOn(); return; }
          if (action === "off") { powerOff(); return; }
          if (action === "sos") { $scope.pressSOS(); return; }
          if (action === "ok") { $scope.pressOK(); return; }
          if (action === "flag") { $scope.pressFlag(); return; }
        });
      }
      if (typeof window !== "undefined") {
        window.addEventListener("message", function (ev) {
          if (ev && ev.data && ev.data.type === "RaceManagerStellaKey") onStellaKey(ev.data);
        });
      }
      // BeamNG guihooks path
      try {
        if (typeof $scope.$on === "function") {
          $scope.$on("RaceManagerStellaKey", function (_, data) { onStellaKey(data || {}); });
        }
      } catch (_) {}
      // Polling fallback via global set by Lua is unnecessary; guihooks is enough.

      // Restore visibility if UI reloaded during an active race
      setTimeout(function () {
        if (typeof bngApi !== 'undefined') {
          bngApi.engineLua('if extensions.bajaStella then extensions.bajaStella.requestState() elseif extensions.gameCommands then extensions.gameCommands.requestStellaState() end');
        }
      }, 600);

      $scope.$on('BajaI18n_Changed', function () {
        $scope.$applyAsync();
      });

    }]
  };
});
