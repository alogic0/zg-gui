import { createNodeRegistry } from './node-registry.js';
import { localDatetime, localTimeLabel, applyInitialTimeFormats } from './local-datetime.js';

const decoder = new TextDecoder('utf-8');
function toText(payload) {
  if (typeof payload === 'string') return payload;
  if (payload instanceof Uint8Array) return decoder.decode(payload);
  if (payload instanceof ArrayBuffer) return decoder.decode(new Uint8Array(payload));
  return String(payload);
}

export function calculateWindowSlice({ scrollTop = 0, viewportHeight = 0, itemHeight = 40, totalItems = 0, overscan = 3 } = {}) {
  if (itemHeight <= 0 || totalItems <= 0) {
    return { startIndex: 0, endIndex: 0, topSpacer: 0, bottomSpacer: 0, totalHeight: 0 };
  }
  const totalHeight = Math.min(totalItems * itemHeight, 0x7fffffff);
  const visibleStart = Math.floor(scrollTop / itemHeight);
  const visibleCount = Math.ceil(viewportHeight / itemHeight);
  const start = Math.max(0, visibleStart > overscan ? visibleStart - overscan : 0);
  const clampedStart = Math.min(start, totalItems);
  const rawEnd = visibleStart + visibleCount + overscan;
  const end = Math.min(totalItems, rawEnd);
  const clampedEnd = Math.max(clampedStart, end);
  const topSpacer = clampedStart * itemHeight;
  const bottomSpacer = (totalItems - clampedEnd) * itemHeight;
  return {
    startIndex: clampedStart,
    endIndex: clampedEnd,
    topSpacer,
    bottomSpacer,
    totalHeight,
  };
}

// Only this module writes the DOM after initialization. Hooks bind host-owned
// capabilities to explicitly introduced subtrees; they do not choose UI state.
export function createDomHost({ root, onStructure = () => {} }) {
  const document = root.ownerDocument;
  const window = document.defaultView;
  let patchTextFocus = null;
  const nodes = createNodeRegistry({ root });
  const patchNode = nodes.get;

  // Attribute names Zig is allowed to set through the A/R operations. Names
  // are Zig literals, so this is defense in depth: an unexpected name fails
  // the stream (and resyncs) instead of reaching setAttribute.
  const attributePattern = /^(?:viewBox|d|fill|stroke|stroke-width|x|y|x1|x2|y1|y2|cx|cy|r|rx|ry|width|height|points|transform|id|for|class|lang|dir|hidden|disabled|required|readonly|datetime|draggable|inert|role|title|href|src|alt|type|name|placeholder|autofocus|autocomplete|min|max|step|minlength|maxlength|colspan|rowspan|aria-[a-z]+(?:-[a-z]+)*|data-[a-z]+(?:-[a-z]+)*)$/;

  function scrollPosition(value, target) {
    if (!(target instanceof window.HTMLElement) || !/^(0|[1-9][0-9]*)$/.test(value) || Number(value) > 16777216) {
      throw new Error('Zig scroll position requires an HTML element and bounded nonnegative pixels');
    }
    return Number(value);
  }
  // Custom properties declared in a data-style-vars attribute
  // ("--bar-width:37;--chart-first:12"). Inline style attributes are blocked
  // by the page's style-src policy; CSSOM writes are not, so Zig declares
  // the values and the host applies them. Names and values are bounded.
  function applyDeclaredStyles(scope) {
    const elements = scope.matches?.("[data-style-vars]") ? [scope] : [];
    elements.push(...scope.querySelectorAll("[data-style-vars]"));
    for (const element of elements) {
      for (const declaration of element.getAttribute("data-style-vars").split(";")) {
        const separator = declaration.indexOf(":");
        if (separator <= 0) continue;
        const property = declaration.slice(0, separator).trim();
        const value = declaration.slice(separator + 1).trim();
        if (!/^--[a-z][a-z0-9-]*$/.test(property) || !/^-?[0-9]+(?:\.[0-9]+)?(?:px|%)?$/.test(value)) {
          throw new Error(`Zig declared an unsupported style variable: ${declaration}`);
        }
        element.style.setProperty(property, value);
      }
    }
    const scrollers = scope.matches?.('[data-scroll-top]') ? [scope] : [];
    scrollers.push(...scope.querySelectorAll('[data-scroll-top]'));
    for (const node of scrollers) node.scrollTop = scrollPosition(node.getAttribute('data-scroll-top'), node);
  }

  // Zig declares the controlled value; structural option changes must restore it.
  function applySelectValues(scope) {
    const selector = 'select[data-select-value], select[data-select-values]';
    const nodes = scope.matches?.(selector) ? [scope] : [];
    nodes.push(...scope.querySelectorAll(selector));
    const parent = scope.closest?.(selector);
    if (parent && !nodes.includes(parent)) nodes.push(parent);
    for (const select of nodes) {
      if (select.multiple && select.dataset.selectValues !== undefined) {
        const raw = select.dataset.selectValues;
        const values = new Set(raw ? raw.split('\x1f') : []);
        for (const opt of select.options) {
          opt.selected = values.has(opt.value);
        }
      } else if (select.dataset.selectValue !== undefined) {
        select.value = select.dataset.selectValue;
      }
    }
  }
  function applyDeclaredProviders(scope) { onStructure(scope); }
  function applyWindowScrollers(scope) {
    const scrollers = scope.matches?.('[data-window-item-height]') ? [scope] : [];
    scrollers.push(...scope.querySelectorAll('[data-window-item-height]'));
    for (const container of scrollers) {
      const itemHeight = Number(container.getAttribute('data-window-item-height') || 40);
      const overscan = Number(container.getAttribute('data-window-overscan') || 3);
      container.style.setProperty('--window-item-height', `${itemHeight}px`);
      container.style.setProperty('--window-overscan', `${overscan}`);
    }
  }

  function hydrate(html) {
    const hasExistingNodes = root.firstElementChild && root.querySelector('[data-node-id]');
    if (!hasExistingNodes) {
      return initialize(html);
    }
    try {
      nodes.rebuild();
      const active = document.activeElement;
      const activeInRoot = active instanceof window.HTMLElement && root.contains(active);
      const activeIsText = active instanceof window.HTMLInputElement || active instanceof window.HTMLTextAreaElement;
      const draftValue = activeIsText ? active.value : null;

      applySelectValues(root);
      applyDeclaredStyles(root);
      applyInitialTimeFormats(root);
      applyWindowScrollers(root);
      onStructure(root);

      if (activeInRoot && activeIsText && draftValue !== null && active.value !== draftValue) {
        active.value = draftValue;
      }
    } catch (err) {
      initialize(html);
      throw err;
    }
  }

  function initialize(html, { hydrate: shouldHydrate = false } = {}) {
    if (shouldHydrate) {
      return hydrate(html);
    }
    root.innerHTML = toText(html);
    nodes.rebuild();
    applySelectValues(root);
    applyDeclaredStyles(root);
    applyInitialTimeFormats(root);
    applyWindowScrollers(root);
    onStructure(root);
  }

  const exiting = new Map(); // target -> { id, transitionName, parent, timeoutId, onEnd }

  function abortExit(target) {
    const info = exiting.get(target);
    if (!info) return;
    clearTimeout(info.timeoutId);
    target.removeEventListener('transitionend', info.onEnd);
    target.removeEventListener('animationend', info.onEnd);
    target.classList.remove('zg-exit', 'zg-exit-active', `${info.transitionName}-exit`, `${info.transitionName}-exit-active`);
    target.style.pointerEvents = '';
    target.removeAttribute('aria-hidden');
    exiting.delete(target);
  }

  function finishExit(target) {
    const info = exiting.get(target);
    if (!info) return;
    clearTimeout(info.timeoutId);
    target.removeEventListener('transitionend', info.onEnd);
    target.removeEventListener('animationend', info.onEnd);
    exiting.delete(target);
    if (target.parentElement) {
      nodes.forget(target);
      target.remove();
      applySelectValues(info.parent);
    }
  }

  function startExit(target, transitionName, parent) {
    if (exiting.has(target)) return;
    const timeoutAttr = target.getAttribute("data-exit-timeout");
    const timeoutMs = timeoutAttr && /^\d+$/.test(timeoutAttr) ? Number(timeoutAttr) : 500;

    target.style.pointerEvents = "none";
    target.setAttribute("aria-hidden", "true");
    target.classList.add("zg-exit", `${transitionName}-exit`);

    if (typeof target.offsetWidth === 'number') {
      void target.offsetWidth;
    }

    target.classList.add("zg-exit-active", `${transitionName}-exit-active`);

    const onEnd = (event) => {
      if (event.target === target) {
        finishExit(target);
      }
    };

    const timeoutId = setTimeout(() => {
      finishExit(target);
    }, timeoutMs);

    target.addEventListener("transitionend", onEnd);
    target.addEventListener("animationend", onEnd);

    exiting.set(target, {
      id: target.getAttribute("data-node-id"),
      transitionName,
      parent,
      timeoutId,
      onEnd,
    });
  }

  function applyPatchStream(stream) {
    patchTextFocus = null;
    const text = toText(stream);
    for (const line of text.split("\n")) {
      if (!line) continue;
      const fields = line.split("\t");
      const operation = fields[0];
      const target = patchNode(fields[1] || "");
      if (operation === "F" && fields.length === 3 && fields[2] === "nearest") {
        if (!(target instanceof window.HTMLElement)) throw new Error("Zig visible focus patch needs an HTML element");
        target.focus({ preventScroll: true });
        target.scrollIntoView({ block: "nearest", inline: "nearest", behavior: "instant" });
        continue;
      }
      if (operation === "F" && fields.length === 3 && fields[2] === "end") {
        if (!(target instanceof window.HTMLTextAreaElement)
          && !(target instanceof window.HTMLInputElement && ["text", "search", "tel", "url", "password"].includes(target.type))) {
          throw new Error("Zig text-end focus patch needs a text control");
        }
        patchTextFocus = target;
        continue;
      }
      if (operation === "F" && fields.length === 2) {
        if (!(target instanceof window.HTMLElement)) throw new Error("Zig focus patch needs an HTML element");
        target.focus({ preventScroll: true });
        continue;
      }
      if (operation === "D" && fields.length === 2) {
        if (target === root || !target.parentElement) throw new Error("Zig remove patch needs an owned child subtree");
        const parent = target.parentElement;
        const transitionName = target.getAttribute("data-exit-transition");
        const reducedMotion = window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches;
        if (!transitionName || reducedMotion) {
          abortExit(target);
          nodes.forget(target);
          target.remove();
          applySelectValues(parent);
          continue;
        }
        startExit(target, transitionName, parent);
        continue;
      }
      if (operation === "C" && fields.length === 3) {
        if (!(target instanceof window.HTMLInputElement)
          || !["checkbox", "radio"].includes(target.type)
          || !["true", "false"].includes(fields[2])) {
          throw new Error(`Zig checked patch node ${fields[1]} requires a checkbox or radio and Boolean payload`);
        }
        target.checked = fields[2] === "true";
        continue;
      }
      if ((operation === "H" || operation === "J" || operation === "T" || operation === "V") && fields.length === 3) {
        const fragment = JSON.parse(fields[2]);
        if (typeof fragment !== "string") {
          throw new Error(`Zig ${operation} patch payload must be a string`);
        }
        if (operation === "V") {
          if (!(target instanceof window.HTMLInputElement)
            && !(target instanceof window.HTMLTextAreaElement)
            && !(target instanceof window.HTMLSelectElement)) {
            throw new Error(`Zig value patch node ${fields[1]} is not a form control`);
          }
          const formatted = target.dataset.valueFormat === 'instant-local' ? localDatetime(fragment) : fragment;
          if (target.value !== formatted) {
            target.value = formatted;
          }
          continue;
        }
        if (operation === "T") {
          nodes.forgetChildren(target);
          target.textContent = localTimeLabel(fragment, { format: target.dataset.textFormat || 'plain' });
          if (target instanceof window.HTMLOptionElement) applySelectValues(target);
          continue;
        }
        if (operation === "J") {
          if (!(target instanceof window.HTMLElement) && !(target instanceof window.SVGElement)) throw new Error("Zig append patch needs an HTML or SVG element");
          const last = target.lastElementChild;
          target.insertAdjacentHTML("beforeend", fragment);
          applySelectValues(target);
          let child = last ? last.nextElementSibling : target.firstElementChild;
          while (child) {
            const nextChild = child.nextElementSibling;
            const childId = child.getAttribute("data-node-id");
            if (childId) {
              const exitingTarget = Array.from(exiting.keys()).find(n => n.getAttribute("data-node-id") === childId);
              if (exitingTarget && exitingTarget !== child) {
                abortExit(exitingTarget);
                const tName = exitingTarget.getAttribute("data-exit-transition");
                exitingTarget.classList.add("zg-enter", `${tName}-enter`);
                if (typeof exitingTarget.offsetWidth === 'number') {
                  void exitingTarget.offsetWidth;
                }
                exitingTarget.classList.add("zg-enter-active", `${tName}-enter-active`);
                const onEnterEnd = (e) => {
                  if (e.target === exitingTarget) {
                    exitingTarget.classList.remove("zg-enter", "zg-enter-active", `${tName}-enter`, `${tName}-enter-active`);
                    exitingTarget.removeEventListener("transitionend", onEnterEnd);
                    exitingTarget.removeEventListener("animationend", onEnterEnd);
                  }
                };
                exitingTarget.addEventListener("transitionend", onEnterEnd);
                exitingTarget.addEventListener("animationend", onEnterEnd);

                child.remove();
                child = nextChild;
                continue;
              }
            }
            nodes.add(child);
            applyDeclaredStyles(child);
            applyDeclaredProviders(child);
            applyInitialTimeFormats(child);
            applyWindowScrollers(child);
            child = nextChild;
          }
          continue;
        }
        const active = document.activeElement;
        const activeInside = active instanceof window.HTMLElement && target.contains(active);
        const activeId = activeInside ? active.id : "";
        const activeTestId = activeInside ? active.getAttribute("data-testid") || "" : "";
        const activeIsTextControl = active instanceof window.HTMLInputElement
          || active instanceof window.HTMLTextAreaElement;
        const selectionStart = activeIsTextControl ? active.selectionStart : null;
        const selectionEnd = activeIsTextControl ? active.selectionEnd : null;
        for (const [exitingNode] of exiting) {
          if (target.contains(exitingNode)) {
            abortExit(exitingNode);
          }
        }
        nodes.forgetChildren(target);
        target.innerHTML = fragment;
        for (const child of target.children) nodes.add(child);
        applySelectValues(target);
        applyDeclaredStyles(target);
        applyDeclaredProviders(target);
        applyInitialTimeFormats(target);
        applyWindowScrollers(target);
        if (activeId || activeTestId) {
          const replacement = activeId
            ? document.getElementById(activeId)
            : Array.from(target.querySelectorAll("[data-testid]")).find(
              (element) => element.getAttribute("data-testid") === activeTestId,
            );
          if (replacement instanceof window.HTMLElement && target.contains(replacement)) {
            replacement.focus({ preventScroll: true });
            if ((replacement instanceof window.HTMLInputElement
                || replacement instanceof window.HTMLTextAreaElement)
              && selectionStart !== null && selectionEnd !== null) {
              replacement.setSelectionRange(selectionStart, selectionEnd);
            }
          }
        }
        continue;
      }
      if (operation === "M" && fields.length === 4) {
        const sibling = patchNode(fields[2] || "");
        if (sibling.parentElement !== target.parentElement) {
          throw new Error(`Zig move patch nodes ${fields[1]} and ${fields[2]} are not siblings`);
        }
        if (fields[3] !== "before" && fields[3] !== "after") {
          throw new Error(`Zig move patch placement must be before or after: ${fields[3]}`);
        }
        if (target === sibling) throw new Error("Cannot move a node relative to itself");
        if (fields[3] === "after" ? sibling.nextElementSibling === target : sibling.previousElementSibling === target) continue;
        const active = document.activeElement;
        const focused = active instanceof window.HTMLElement && target.contains(active) ? active : null;
        if (fields[3] === "after") sibling.after(target);
        else sibling.before(target);
        applySelectValues(target.parentElement);
        if (focused && focused.isConnected) focused.focus({ preventScroll: true });
        continue;
      }
      const attribute = fields[2] || "";
      if (!attribute) throw new Error("Zig patch omitted an attribute name");
      if (attribute === "value") {
        if (!(target instanceof window.HTMLOptionElement) && (operation !== "A" || !(target instanceof window.HTMLMeterElement || target instanceof window.HTMLProgressElement)
          || !/^[0-9]+(?:\.[0-9]+)?$/.test(fields[3])
          || !Number.isFinite(Number(fields[3]))
          || Number(fields[3]) < (target instanceof window.HTMLProgressElement ? 0 : target.min) || Number(fields[3]) > target.max)) {
          throw new Error("Zig meter/progress value patch requires a finite value within its declared range");
        }
      } else if (attribute === "tabindex") {
        if (operation === "A" && fields[3] !== "-1" && fields[3] !== "0") {
          throw new Error("Zig tabindex patch requires -1 or 0");
        }
      } else if (!attributePattern.test(attribute)) {
        throw new Error(`Zig patch names an attribute outside the allowlist: ${attribute}`);
      }
      if (operation === "A" && fields.length === 4) {
        if (attribute === 'href') {
          const url = new URL(fields[3], document.baseURI);
          if (!['http:', 'https:', 'mailto:', 'tel:'].includes(url.protocol) || url.username || url.password)
            throw new Error('Unsupported link URL');
        }
        if (attribute === 'data-scroll-top') {
          const position = scrollPosition(fields[3], target);
          target.setAttribute(attribute, fields[3]);
          target.scrollTop = position;
          continue;
        }
        if (attribute === "src") {
          const url = new URL(fields[3], document.baseURI);
          const frame = target instanceof window.HTMLIFrameElement;
          const allowed = frame
            ? target.hasAttribute('sandbox') && (fields[3] === 'about:blank'
              || (url.origin === window.location.origin && ['http:', 'https:'].includes(url.protocol))
              || (target.getAttribute('data-external-frame') === 'true' && url.protocol === 'https:'))
            : target instanceof window.HTMLImageElement && (
                (['http:', 'https:'].includes(url.protocol)
                  && (url.origin === window.location.origin || target.getAttribute('data-external-image') === 'true'))
                || (url.protocol === 'blob:' && url.origin === window.location.origin && target.getAttribute('data-object-image') === 'true'));
          if (!allowed || url.username || url.password) {
            throw new Error("Zig source patch requires an explicitly permitted image or sandboxed frame");
          }
        }
        target.setAttribute(attribute, fields[3]);
        if (attribute === "data-select-value" || attribute === "data-select-values" || (attribute === "value" && target instanceof window.HTMLOptionElement)) applySelectValues(target);
        if (attribute === "data-style-vars") applyDeclaredStyles(target);
      } else if (operation === "R" && fields.length === 3) {
        if (attribute === "data-style-vars") {
          for (const declaration of (target.getAttribute(attribute) || '').split(';')) {
            const separator = declaration.indexOf(':');
            if (separator <= 0) continue;
            const property = declaration.slice(0, separator).trim();
            if (/^--[a-z][a-z0-9-]*$/.test(property)) target.style.removeProperty(property);
          }
        }
        target.removeAttribute(attribute);
        if (attribute === "value" && target instanceof window.HTMLOptionElement) applySelectValues(target);
      } else {
        throw new Error(`Unknown or malformed Zig patch operation: ${line}`);
      }
    }
    if (patchTextFocus?.isConnected && !patchTextFocus.closest('[hidden]')) {
      patchTextFocus.focus({ preventScroll: true });
      patchTextFocus.setSelectionRange(patchTextFocus.value.length, patchTextFocus.value.length);
    }
    patchTextFocus = null;
  }

  function dispose() {
    for (const [node] of exiting) abortExit(node);
    nodes.dispose();
  }

  return Object.freeze({ initialize, hydrate, applyPatchStream, dispose });
}
