function execCmd(cmd) {
  document.execCommand(cmd, false, null);
}

function extractFormData() {
  var data = {};
  var els = document.querySelectorAll("input,select,textarea");
  for (var i = 0; i < els.length; i++) {
    var el = els[i];
    if (el.name) {
      if (el.type === "checkbox") data[el.name] = el.checked;
      else data[el.name] = el.value;
    }
  }
  var rts = document.querySelectorAll("[contenteditable][data-name]");
  for (var i = 0; i < rts.length; i++) {
    data[rts[i].getAttribute("data-name")] = rts[i].innerHTML;
  }
  return data;
}

function setFormData(json) {
  var data = JSON.parse(json);
  for (var key in data) {
    if (data.hasOwnProperty(key)) {
      var el = document.querySelector('[name="' + key + '"]');
      if (!el) el = document.querySelector('[data-name="' + key + '"]');
      if (el) {
        if (el.hasAttribute("contenteditable")) el.innerHTML = data[key];
        else if (el.type === "checkbox") el.checked = data[key];
        else if (el.tagName === "TEXTAREA") { el.textContent = data[key]; el.value = data[key]; }
        else el.value = data[key];
      }
    }
  }
}

function disableAllInputs() {
  var els = document.querySelectorAll("input,select,textarea");
  for (var i = 0; i < els.length; i++) {
    els[i].disabled = true;
    els[i].style.backgroundColor = "#f5f5f5";
    els[i].style.cursor = "default";
  }
  var rts = document.querySelectorAll("[contenteditable]");
  for (var i = 0; i < rts.length; i++) {
    rts[i].removeAttribute("contenteditable");
    rts[i].parentElement.classList.add("rt-disabled");
  }
}

// Posts 'dirty' to the host once on the first user edit. Programmatic
// value assignment (setFormData) does not fire input/change events, so
// arming before or after setFormData is safe.
function armDirtyTracking() {
  var fired = false;
  function fire() {
    if (fired) return;
    fired = true;
    try { window.chrome.webview.postMessage("dirty"); } catch (e) {}
  }
  document.addEventListener("input", fire, true);
  document.addEventListener("change", fire, true);
}
