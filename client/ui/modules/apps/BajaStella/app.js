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
      'width:1280px;height:720px;max-width:100%;max-height:100%;position:relative;overflow:hidden;' +
      'pointer-events:auto;z-index:100;' +
      'display:flex;flex-direction:column;cursor:move;padding:3px 3px 4px;' +
      'background:transparent url(' + ASSETS + 'stella_device.png) center/100% 100% no-repeat;' +
      'border:0;border-radius:0;' +
      'font-family:"Bahnschrift","Arial Narrow","Segoe UI",sans-serif;' +
      'user-select:none;-webkit-user-select:none;' +
      'box-shadow:inset 0 0 0 1px rgba(255,255,255,.14),inset 0 -3px 8px rgba(0,0,0,.72),0 10px 22px rgba(0,0,0,.58);' +
    '}' +
    '#stella-dev::before{display:none;}' +
    '#stella-dev.st-off{opacity:0;pointer-events:none;}' +

    /* === Header === */
    '.st-hdr{display:none;height:33px;}' +
      'background:linear-gradient(180deg,#26262d,#0f1015);border-bottom:1px solid rgba(255,255,255,.09);}' +
    '.st-hdr-left{width:1px;height:1px;}' +
    '.st-hdr-mid{display:flex;align-items:center;justify-content:center;min-width:0;}' +
    '.st-hdr-right{display:flex;align-items:center;justify-content:flex-end;}' +
    '.st-logo-img{height:18px;width:auto;display:block;image-rendering:crisp-edges;}' +
    '.st-logo-txt{color:#d8dbe6;font-size:10px;font-weight:700;letter-spacing:1px;}' +
    '.st-rnum{margin-left:0;color:#d7d8de;font-size:15px;font-weight:700;font-style:italic;letter-spacing:1px;opacity:.96;}' +

    /* === LCD === */
    '.st-lcd{position:absolute;left:213px;top:159px;width:852px;height:305px;margin:0;border-radius:0;overflow:hidden;' +
      'background:linear-gradient(160deg,#d6ebff 0%,#c8e2f9 50%,#bbd7f0 100%);' +
      'padding:0 10px 8px !important;box-shadow:none;background:rgba(190,221,250,.88);}' +
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
    '.lcd-caution,.lcd-bf-overlay,.lcd-flag-overlay{display:none!important;}' +
    '@keyframes stCaution{0%,100%{opacity:1}50%{opacity:.22}}' +
    '.lcd-caution-txt{font-size:18px;font-weight:800;color:#523d04;letter-spacing:4px;animation:stCaution 1s ease-in-out infinite;}' +
    '.lcd-flag-overlay{position:absolute;left:0;right:0;bottom:4px;z-index:10;display:flex;justify-content:center;pointer-events:none;}' +
    '.lcd-flag-pill{background:rgba(18,94,225,.2);border:1px solid rgba(18,94,225,.5);border-radius:3px;padding:1px 9px;}' +
    '.lcd-flag-txt{font-size:10px;letter-spacing:1px;}' +

    /* === Speed zone overlay === */
    '.lcd-sz-overlay{position:absolute;right:0;top:0;width:330px;height:100%;z-index:9;pointer-events:none;display:flex;flex-direction:column;align-items:center;justify-content:center;transition:opacity .3s;}' +
    '.lcd-sz-overlay.sz-warn{background:rgba(212,170,18,.12);}' +
    '.lcd-sz-overlay.sz-exceed{background:rgba(210,30,20,.16);}' +
    '@keyframes szPulse{0%,100%{opacity:1}50%{opacity:.3}}' +
    '.lcd-sz-limit{font-size:36px;font-weight:800;color:#523d04;letter-spacing:2px;line-height:1;}' +
    '.lcd-sz-limit.sz-red{color:#8b1a12;}' +
    '.lcd-sz-label{font-size:10px;font-weight:700;color:#5a5024;letter-spacing:2px;text-transform:uppercase;}' +
    '.lcd-sz-label.sz-red{color:#8b1a12;animation:szPulse .6s ease-in-out infinite;}' +
    '.lcd-sz-unit{font-size:14px;font-weight:700;color:#6b6232;margin-left:2px;}' +
    '.lcd-sz-unit.sz-red{color:#8b1a12;}' +

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
    '.st-bot{position:absolute;left:213px;top:487px;width:852px;height:174px;display:flex;align-items:center;gap:8px;padding:0;}' +
    '.st-led-blk{position:absolute;left:0;top:0;width:365px;height:174px;display:flex;align-items:center;}' +
    '.st-led-num{display:none;}' +
    '.st-led-mx{width:365px;height:174px;display:grid;grid-template-columns:repeat(10,1fr);grid-template-rows:repeat(5,1fr);gap:5px;' +
      'padding:3px;background:#15151b;border:1px solid #4a4a4e;border-radius:2px;box-shadow:inset 0 3px 8px rgba(0,0,0,.7);}' +
    '.st-led-d{border-radius:50%;opacity:.95;background:radial-gradient(circle at 50% 52%,#1d1e24 30%,#787469 33%,#262730 67%);}' +
    '.st-led-mx.l-green .st-led-d.st-led-on{background:radial-gradient(circle,#9dff95 20%,#20c53f 48%,#153b1d 70%);box-shadow:0 0 5px rgba(53,220,70,.55);}' +
    '.st-led-mx.l-yellow .st-led-d.st-led-on{background:radial-gradient(circle,#fff2a0 20%,#d4bb22 48%,#483f17 70%);box-shadow:0 0 5px rgba(220,190,35,.55);}' +
    '.st-led-mx.l-red .st-led-d.st-led-on{background:radial-gradient(circle,#ffb2ab 20%,#d33426 48%,#4b1d18 70%);box-shadow:0 0 5px rgba(230,70,56,.55);}' +
    '.st-led-mx.l-blue .st-led-d.st-led-on{background:radial-gradient(circle,#b5ddff 20%,#2e8fe2 48%,#17344c 70%);box-shadow:0 0 5px rgba(65,150,230,.55);}' +
    '@keyframes stFlash{0%,100%{opacity:1}50%{opacity:.1}}' +
    '.st-led-mx.l-flash .st-led-d.st-led-on{animation:stFlash .55s ease-in-out infinite;}' +
    '.st-btns{position:absolute;left:365px;top:0;width:487px;height:174px;display:flex;flex-direction:column;justify-content:flex-end;min-width:0;}' +
    '.st-btn-row{height:122px;display:flex;border:0;box-shadow:none;overflow:visible;position:relative;}' +
    '.st-btn{border:none;border-radius:0;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:3px;' +
      'font-family:"Bahnschrift","Segoe UI",sans-serif;font-weight:700;color:#fff;transition:filter .1s,transform .08s;}' +
    '.st-btn:active{transform:scale(.98);filter:brightness(.9);}' +
    '.st-btn img{display:none;}' +
    '.st-btn-sos{flex:1;background:transparent;border-radius:20px 0 0 20px;}' +
    '.st-btn-sos img{filter:brightness(0) invert(1);}' +
    '.st-btn-ok{flex:1;background:transparent;font-size:18px;line-height:1;color:transparent;}' +
    '.st-btn-flag{flex:1;background:transparent;border-left:0;border-radius:0 20px 20px 0;color:transparent;}' +
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

    /* The photograph is authoritative: these are only transparent interaction and
       telemetry layers positioned over the matching features in the photograph. */
    '#stella-dev .lcd-main{display:grid;}' +
    '#stella-dev .lcd-main.ng-hide{display:none;}' +
    '#stella-dev .lcd-apr{display:none!important;}' +
    '#stella-dev .lcd-hdg{font-size:190px;line-height:.78;letter-spacing:-9px;}' +
    '#stella-dev .lcd-hdg sup{font-size:72px;}' +
    '#stella-dev .lcd-wp{font-size:55px;line-height:.9;max-width:410px;margin-top:10px;}' +
    '#stella-dev .lcd-dist-vcp,#stella-dev .lcd-total{font-size:150px;line-height:.78;letter-spacing:-7px;}' +
    '#stella-dev .lcd-right{min-width:350px;}' +
    '#stella-dev .lcd-km-lbl{font-size:25px;padding-bottom:14px;}' +
    '#stella-dev .lcd-odo-lbl{font-size:19px;margin-top:8px;}' +
    '#stella-dev .lcd-track{font-size:18px;bottom:8px;}' +
    '#stella-dev .lcd-speed{position:absolute;right:18px;bottom:8px;font-size:25px;letter-spacing:1px;}' +
    '#stella-dev .st-sos-bar{display:none;}' +
    '#stella-dev .st-led-num{display:none;}' +
    '#stella-dev .st-led-mx{background:transparent;border:0;box-shadow:none;}' +
    '#stella-dev .st-led-d{opacity:.18;}' +
    '#stella-dev .st-led-msg{position:absolute;inset:8px;z-index:3;display:flex;align-items:center;justify-content:center;' +
      'color:#f5e36b;text-align:center;font-size:34px;line-height:1.05;font-weight:800;letter-spacing:3px;text-shadow:0 0 8px currentColor;}' +
    '#stella-dev .st-led-msg.msg-red{color:#ff4538;}#stella-dev .st-led-msg.msg-blue{color:#65b8ff;}' +
    '#stella-dev .st-led-msg.msg-green{color:#79ed8a;}' +
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
    '<div id="stella-dev" ng-class="{\'st-off\': !visible}" ng-mousedown="dragStart($event)" style="width:1280px;height:720px">' +

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
          'ng-class="{\'bf-incoming\': flagState===\'incoming\', \'bf-requesting\': flagState===\'requested\', \'bf-acknowledged\': flagState===\'delivered\', \'bf-acked\': flagState===\'go\'}">' +
        '</div>' +

        /* Speed zone overlay */
        '<div class="lcd-sz-overlay" ng-show="szActive" ng-class="{\x27sz-warn\x27: szActive && !szExceeding, \x27sz-exceed\x27: szExceeding}">' +
          '<div class="lcd-sz-label" ng-class="{\x27sz-red\x27: szExceeding}">{{szExceeding ? tr("stella.speedZone.limit","\\u26A0 SPEED LIMIT") : tr("stella.speedZone.zone","SPEED ZONE")}}</div>' +
          '<div class="lcd-sz-limit" ng-class="{\x27sz-red\x27: szExceeding}">{{szLimitMph}}<span class="lcd-sz-unit" ng-class="{\x27sz-red\x27: szExceeding}">mph</span></div>' +
          '<div class="lcd-sz-label" ng-show="szExceeding" ng-class="{\x27sz-red\x27: szExceeding}">{{tr("stella.speedZone.reduce","REDUCE SPEED")}}</div>' +
        '</div>' +

        /* Blue flag overlay */
        '<div class="lcd-flag-overlay" ng-show="flagState===\'incoming\'">' +
          '<div class="lcd-flag-pill"><span class="lcd-flag-txt lc">{{tr("stella.flag.overtake","ADELANTAR")}} \u2014 {{flagPlayer}}</span></div>' +
        '</div>' +

        /* Idle mode */
        '<div class="lcd-idle" ng-show="!raceActive">' +
          '<div class="lc lc-label lcd-idle-lbl">{{tr("stella.idle.ready","READY")}}</div>' +
          '<div class="lc lcd-idle-hdg">{{hdg}}<sup>\u00B0</sup></div>' +
          '<div class="lc lcd-idle-spd">{{spd}}<span class="lc-dim lcd-idle-unit">{{tr("stella.unit.kmh","km/h")}}</span></div>' +
        '</div>' +

        /* Normal race mode */
        '<div class="lcd-main" ng-show="raceActive">' +
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
          '<div class="lc lcd-speed" ng-show="szActive">{{spdMph}} / {{szLimitMph}} mph</div>' +
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
          '<div class="st-led-msg" ng-class="ledMsgClass">{{ledMessage}}</div>' +
        '</div>' +
        '<div class="st-btns">' +
          '<div class="st-btn-row">' +
            '<button class="st-btn st-btn-sos" ng-mousedown="pressSOSStart($event)" ng-mouseup="pressSOSCancel($event)" ng-mouseleave="pressSOSCancel($event)" ng-touchstart="pressSOSStart($event)" ng-touchend="pressSOSCancel($event)" data-tip="{{tr(\'stella.tip.assistance\',\'Asistencia Mecanica\')}}">' +
              '<img src="' + ASSETS + 'sos.svg" alt="">' +
            '</button>' +
            '<button class="st-btn st-btn-ok" ng-click="pressOK()" ng-mousedown="$event.stopPropagation()" data-tip="{{tr(\'stella.tip.confirm\',\'Confirmar\')}}">OK</button>' +
            '<button class="st-btn st-btn-flag" ng-click="pressFlag()" ng-mousedown="$event.stopPropagation()" ng-class="{\'fl-active\': flagState!==\'none\'}" data-tip="{{tr(\'stella.tip.overtake\',\'Adelantar\')}}">' +
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
      $scope.visible     = false;
      $scope.hdg         = '000';
      $scope.spd         = '0';
      $scope.spdMph      = '0';
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
      $scope.ledMessage  = '';
      $scope.ledMsgClass = '';

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

      function updateLedMessage() {
        var msg = '', cls = '';
        if ($scope.hazardAhead) { msg = '▲'; cls = 'msg-red'; }
        else if ($scope.breakdownActive) { msg = '▲'; }
        else if ($scope.flagState === 'incoming') { msg = 'BLUE FLAG'; cls = 'msg-blue'; }
        else if ($scope.flagState === 'requested') { msg = 'BLUE'; cls = 'msg-blue'; }
        else if ($scope.flagState === 'delivered') { msg = 'SENT'; cls = 'msg-green'; }
        else if ($scope.flagState === 'go') { msg = 'GO'; cls = 'msg-green'; }
        else if ($scope.flagState === 'accepted') { msg = 'PASS'; cls = 'msg-blue'; }
        else if ($scope.szActive || $scope.szWarning) { msg = ($scope.szExceeding ? '▲ ' : '') + $scope.szLimitMph + ' MPH'; cls = $scope.szExceeding ? 'msg-red' : ''; }
        else if ($scope.cautionAhead) { msg = '▲ CAUTION'; }
        $scope.ledMessage = msg;
        $scope.ledMsgClass = cls;
      }

      $scope.ledDotClass = function (idx) {
        return ($scope._ledMask && $scope._ledMask[idx]) ? 'st-led-on' : '';
      };

      setLedVisual('off', false, 'none');

      // ---- Drag ----
      $scope.dragStart = function (e) {
        if (e.button !== 0) return;
        var el = document.getElementById('stella-dev');
        if (!el) return;
        var wrap = el.parentElement;
        while (wrap && wrap !== document.body) {
          if (/absolute|fixed/.test(window.getComputedStyle(wrap).position)) break;
          wrap = wrap.parentElement;
        }
        if (!wrap || wrap === document.body) return;
        var r = wrap.getBoundingClientRect();
        var ox = e.clientX - r.left, oy = e.clientY - r.top;
        function onMove(ev) {
          wrap.style.left = (ev.clientX - ox) + 'px';
          wrap.style.top  = (ev.clientY - oy) + 'px';
        }
        function onUp() {
          document.removeEventListener('mousemove', onMove);
          document.removeEventListener('mouseup', onUp);
        }
        document.addEventListener('mousemove', onMove);
        document.addEventListener('mouseup', onUp);
        e.preventDefault();
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
      var vcpAudio = new Audio('/ui/modules/apps/BajaStella/vcp_sound.mp3');
      try {
        var sv = localStorage.getItem('bajaVcpVolume');
        vcpAudio.volume = (sv !== null) ? parseInt(sv, 10) / 100 : 0.5;
      } catch (_) { vcpAudio.volume = 0.5; }

      function playVCPSound() {
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
          a.volume = vcpAudio.volume;
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
        var a = getSZEntryAudio();
        if (a) { try { a.currentTime = 0; a.play(); } catch (_) {} }
      }

      function startSZExceedLoop() {
        stopSZExceedLoop();
        var a = getSZExceedAudio();
        if (!a) return;
        try { a.currentTime = 0; a.loop = true; a.play(); } catch (_) {}
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
        var a = getOvertakeAudio();
        if (!a) return;
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
      // Volume change from the optional host settings UI
      $scope.$on('BajaVCP_VolumeChange', function (_ev, vol) {
        vcpAudio.volume = Math.max(0, Math.min(1, vol));
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
          $scope.spd        = String(d.speed || 0);
          $scope.spdMph     = String(Math.round((d.speed || 0) * 0.621371));
          $scope.dVCP       = fmtKm(d.distToVCPkm || 0);
          $scope.dMeters    = String(d.distToVCPm || 0);
          $scope.wpName     = d.vcpName || 'VCP';
          $scope.wpLabel    = pad(d.validatedVCPs || 0, 2) + '-WP' + (d.vcpIndex || 0) +
            (d.vcpName ? ' ' + d.vcpName : '');
          $scope.wpKm       = d.distToVCPkm != null ? d.distToVCPkm.toFixed(2) : '0.00';
          $scope.tDist      = fmtKm(d.totalDistKm || 0);
          $scope.raceActive = !!(d.raceActive);
          $scope.approaching = !!(d.isApproaching);
          $scope.isStopped  = !!(d.isStopped);
          $scope.cautionAhead = !!(d.cautionAhead);
          $scope.breakdownActive = !!(d.breakdownActive);
          $scope.hazardAhead = !!(d.hazardAhead);
          $scope.flagState  = d.blueFlagState || 'none';
          $scope.flagPlayer = d.blueFlagPlayer || '';
          var pid = (d.playerId != null) ? Number(d.playerId) : NaN;
          $scope.raceNum    = isNaN(pid) ? pad(d.vcpIndex || 0, 4) : pad(Math.max(0, Math.floor(pid)), 4);
          $scope.trackLabel = '';

          // Speed zone data from stella.lua
          $scope.szActive    = !!(d.speedZoneActive);
          $scope.szWarning   = !!(d.speedZoneWarning);
          $scope.szExceeding = !!(d.speedExceeding);
          $scope.szLimit     = d.speedZoneLimit || 0;
          $scope.szLimitMph  = Math.round($scope.szLimit * 0.621371);
          $scope.szName      = d.speedZoneName || '';

           setLedVisual(d.ledColor, d.ledFlash, d.ledPattern);
           updateLedMessage();

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
           updateLedMessage();
        });
      });

      // ---- Blue flag event ----
      $scope.$on('BajaStella_BlueFlag', function (_ev, d) {
        $scope.$applyAsync(function () {
          var st = (d && d.state) || 'none';
          $scope.flagState  = (st === 'clear') ? 'none' : st;
          $scope.flagPlayer = (d && d.playerName) || '';
           updateLedMessage();
        });
      });

      $scope.$on('BajaStella_AlertSound', function (_ev, d) {
        var loud = !!(d && d.loud);
        var a = initSZAudio('beep_corto.mp3');
        if (!a) return;
        a.volume = loud ? 1 : vcpAudio.volume;
        var remaining = loud ? 5 : 3;
        a.onended = function () {
          remaining--;
          if (remaining > 0) setTimeout(function () {
            try { a.currentTime = 0; a.play(); } catch (_) {}
          }, loud ? 100 : 200);
        };
        try { a.currentTime = 0; a.play(); } catch (_) {}
      });

      // ---- VCP crossed (LED green driven by Lua via BajaStella_LED + BajaStella_Update) ----
      $scope.$on('BajaStella_VCPCrossed', function () { /* LED state managed by stella.lua */ });

      // Local GE proximity warnings (the extension handles cooldown/hysteresis).
      $scope.$on('BajaStella_Proximity', function (_ev, d) {
        if (d && !d.clear) playOvertakeBeep(d.kind === 'rearApproach' ? 3 : 1);
      });

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
        }
      });

      // ---- Button handlers ----
      $scope.pressSOS = function () {
        lua('extensions.bajaStella.requestSOS()');
      };
      var sosHoldTimer = null;
      $scope.pressSOSStart = function (e) {
        if (e && e.stopPropagation) e.stopPropagation();
        if (sosHoldTimer) return;
        sosHoldTimer = setTimeout(function () {
          sosHoldTimer = null;
          $scope.$applyAsync(function () { $scope.pressSOS(); });
        }, 3000);
      };
      $scope.pressSOSCancel = function (e) {
        if (e && e.stopPropagation) e.stopPropagation();
        if (sosHoldTimer) { clearTimeout(sosHoldTimer); sosHoldTimer = null; }
      };
      $scope.pressOK = function () {
        lua('extensions.bajaStella.acknowledgeBlueFlag()');
      };
      $scope.pressFlag = function () {
        if ($scope.flagState === 'incoming') {
          lua('extensions.bajaStella.acknowledgeBlueFlag()');
        } else {
          lua('extensions.bajaStella.requestBlueFlag()');
        }
      };


      // Restore visibility if UI reloaded during an active race
      setTimeout(function () {
        if (typeof bngApi !== 'undefined') {
          bngApi.engineLua('extensions.bajaStella.requestState()');
        }
      }, 600);

      $scope.$on('BajaI18n_Changed', function () {
        $scope.$applyAsync();
      });

    }]
  };
});
