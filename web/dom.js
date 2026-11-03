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
  const attributePattern = /^(?:marker-start|marker-mid|marker-end|stroke-dasharray|text-anchor|dx|dy|viewBox|d|fill|stroke|stroke-width|x|y|x1|x2|y1|y2|cx|cy|r|rx|ry|width|height|points|transform|id|for|class|lang|dir|hidden|disabled|required|readonly|datetime|draggable|inert|role|title|href|src|alt|type|name|placeholder|autofocus|autocomplete|min|max|step|minlength|maxlength|colspan|rowspan|aria-[a-z]+(?:-[a-z]+)*|data-[a-z]+(?:-[a-z]+)*)$/;

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

  function applyFormStates(scope) {
    const selector = 'input, textarea, select';
    const controls = scope.matches?.(selector) ? [scope] : [];
    controls.push(...scope.querySelectorAll(selector));
    for (const control of controls) {
      if (control.type === 'button' || control.type === 'submit' || control.type === 'reset') continue;
      if (!control.hasAttribute('data-dirty') && !control.hasAttribute('data-touched') && !control.hasAttribute('data-pristine')) {
        control.setAttribute('data-pristine', 'true');
      }
    }
  }

  const observedElements = new Set();
  let resizeObserver = null;

  function parseBreakpoints(spec) {
    return spec.split(',').map(part => {
      const [name, widthStr] = part.split(':').map(s => s.trim());
      const width = Number(widthStr);
      return { name, width: Number.isFinite(width) ? width : 0 };
    }).sort((a, b) => a.width - b.width);
  }

  function handleResizeEntries(entries) {
    for (const entry of entries) {
      const target = entry.target;
      if (!(target instanceof window.HTMLElement)) continue;
      const spec = target.getAttribute('data-observe-size');
      if (!spec) continue;
      const breakpoints = parseBreakpoints(spec);
      const width = entry.contentRect.width;
      let matchedSize = 'standard';
      if (breakpoints.length === 1) {
        matchedSize = width < breakpoints[0].width ? breakpoints[0].name : 'standard';
      } else if (breakpoints.length >= 2) {
        if (width < breakpoints[0].width) {
          matchedSize = breakpoints[0].name;
        } else if (width >= breakpoints[breakpoints.length - 1].width) {
          matchedSize = breakpoints[breakpoints.length - 1].name;
        } else {
          matchedSize = 'standard';
        }
      }
      if (target.getAttribute('data-size') !== matchedSize) {
        target.setAttribute('data-size', matchedSize);
      }
    }
  }

  function applyObservedSizes(scope) {
    if (typeof window.ResizeObserver !== 'function') return;
    if (!resizeObserver) {
      resizeObserver = new window.ResizeObserver(handleResizeEntries);
    }
    const selector = '[data-observe-size]';
    const elements = scope.matches?.(selector) ? [scope] : [];
    elements.push(...scope.querySelectorAll(selector));
    for (const el of elements) {
      if (!observedElements.has(el)) {
        observedElements.add(el);
        resizeObserver.observe(el);
      }
    }
  }

  let intersectionObserver = null;
  const hydratedIslands = new WeakSet();

  function activateIsland(island) {
    if (hydratedIslands.has(island)) return;
    hydratedIslands.add(island);
    island.setAttribute('data-hydrated', 'true');
    island.dispatchEvent(new window.CustomEvent('zg:hydrate', { bubbles: true, detail: { island } }));
  }

  function applyIslandHydration(scope) {
    if (typeof window.IntersectionObserver === 'undefined') return;
    const selector = '[data-hydrate]';
    const islands = scope.matches?.(selector) ? [scope] : [];
    islands.push(...scope.querySelectorAll(selector));
    for (const island of islands) {
      if (hydratedIslands.has(island) || island.getAttribute('data-hydrated') === 'true') continue;
      const mode = island.getAttribute('data-hydrate');
      if (mode === 'visible') {
        if (!intersectionObserver) {
          intersectionObserver = new window.IntersectionObserver((entries) => {
            for (const entry of entries) {
              if (entry.isIntersecting) {
                const target = entry.target;
                intersectionObserver.unobserve(target);
                activateIsland(target);
              }
            }
          }, { rootMargin: '100px' });
        }
        intersectionObserver.observe(island);
      } else if (mode === 'idle') {
        const scheduleIdle = window.requestIdleCallback || ((cb) => setTimeout(cb, 50));
        scheduleIdle(() => activateIsland(island));
      }
    }
  }

  const layoutElements = new Set();
  function registerLayoutElements(scope) {
    const selector = '[data-layout-id]';
    const elements = scope.matches?.(selector) ? [scope] : [];
    elements.push(...scope.querySelectorAll(selector));
    for (const el of elements) layoutElements.add(el);
  }

  const flipFirst = new Map();
  function captureFlipFirst() {
    if (layoutElements.size === 0) return;
    for (const el of layoutElements) {
      if (!el.isConnected) {
        layoutElements.delete(el);
        continue;
      }
      const id = el.getAttribute('data-layout-id');
      if (id) {
        const rect = el.getBoundingClientRect();
        flipFirst.set(id, { left: rect.left, top: rect.top });
      }
    }
  }

  function playFlipTransitions() {
    if (flipFirst.size === 0) return;
    if (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      flipFirst.clear();
      return;
    }
    for (const el of layoutElements) {
      if (!el.isConnected) {
        layoutElements.delete(el);
        continue;
      }
      const id = el.getAttribute('data-layout-id');
      const first = flipFirst.get(id);
      if (!first) continue;
      const last = el.getBoundingClientRect();
      const dx = first.left - last.left;
      const dy = first.top - last.top;
      if (dx !== 0 || dy !== 0) {
        el.style.transform = `translate(${dx}px, ${dy}px)`;
        el.style.transition = 'none';
        window.requestAnimationFrame(() => {
          el.style.transition = 'transform 200ms cubic-bezier(0.2, 0, 0, 1)';
          el.style.transform = '';
          const onEnd = (e) => {
            if (e.target === el) {
              el.style.transition = '';
              el.removeEventListener('transitionend', onEnd);
            }
          };
          el.addEventListener('transitionend', onEnd);
        });
      }
    }
    flipFirst.clear();
  }

  const optimisticBuffer = new Map();

  function applyOptimistic(target, { actionId, updates = {} } = {}) {
    if (!(target instanceof window.HTMLElement)) throw new Error('Target must be an HTMLElement');
    if (!actionId) throw new Error('actionId is required for optimistic updates');
    const attrs = [];
    for (let i = 0; i < target.attributes.length; i++) {
      const a = target.attributes[i];
      attrs.push({ name: a.name, value: a.value });
    }
    optimisticBuffer.set(actionId, {
      target,
      textContent: target.textContent,
      className: target.className,
      attributes: attrs,
    });
    target.setAttribute('data-optimistic-state', 'pending');
    if (updates.textContent !== undefined) target.textContent = updates.textContent;
    if (updates.className !== undefined) target.className = updates.className;
    if (updates.attributes) {
      for (const [k, v] of Object.entries(updates.attributes)) {
        if (v === null) target.removeAttribute(k);
        else target.setAttribute(k, v);
      }
    }
  }

  function confirmOptimistic(actionId) {
    const entry = optimisticBuffer.get(actionId);
    if (!entry) return false;
    entry.target.setAttribute('data-optimistic-state', 'confirmed');
    optimisticBuffer.delete(actionId);
    return true;
  }

  function rollbackOptimistic(actionId) {
    const entry = optimisticBuffer.get(actionId);
    if (!entry) return false;
    const { target, textContent, className, attributes } = entry;
    while (target.attributes.length > 0) {
      target.removeAttribute(target.attributes[0].name);
    }
    for (const attr of attributes) {
      target.setAttribute(attr.name, attr.value);
    }
    target.className = className;
    target.textContent = textContent;
    target.setAttribute('data-optimistic-state', 'reverted');
    optimisticBuffer.delete(actionId);
    return true;
  }

  function handleControlBlur(event) {
    const target = event.target;
    if (!target || !root.contains(target)) return;
    if (target instanceof window.HTMLInputElement || target instanceof window.HTMLTextAreaElement || target instanceof window.HTMLSelectElement) {
      if (target.type === 'button' || target.type === 'submit' || target.type === 'reset') return;
      target.setAttribute('data-touched', 'true');
    }
  }

  function handleControlInput(event) {
    const target = event.target;
    if (!target || !root.contains(target)) return;
    if (target instanceof window.HTMLInputElement || target instanceof window.HTMLTextAreaElement || target instanceof window.HTMLSelectElement) {
      if (target.type === 'button' || target.type === 'submit' || target.type === 'reset') return;
      target.setAttribute('data-dirty', 'true');
      target.removeAttribute('data-pristine');
    }
  }

  let previousActiveElement = null;

  function getFocusableElements(container) {
    const selector = 'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';
    return Array.from(container.querySelectorAll(selector)).filter(el => {
      return el instanceof window.HTMLElement && !el.hidden && !el.closest('[hidden]') && el.style.display !== 'none' && el.style.visibility !== 'hidden';
    });
  }

  function handleKeyDown(event) {
    if (!event || !event.key) return;

    // 1. Focus trapping inside active modal/dialog
    const activeTrap = root.querySelector('[data-trap-focus="true"], dialog[open]');
    if (activeTrap && !activeTrap.hidden && !activeTrap.closest('[hidden]')) {
      if (event.key === 'Tab') {
        const focusables = getFocusableElements(activeTrap);
        if (focusables.length > 0) {
          const first = focusables[0];
          const last = focusables[focusables.length - 1];
          const current = document.activeElement;
          if (event.shiftKey) {
            if (current === first || !activeTrap.contains(current)) {
              event.preventDefault();
              last.focus();
              return;
            }
          } else {
            if (current === last || !activeTrap.contains(current)) {
              event.preventDefault();
              first.focus();
              return;
            }
          }
        }
      } else if (event.key === 'Escape') {
        event.preventDefault();
        const closeBtn = activeTrap.querySelector('[data-close-dialog], button[aria-label*="close" i], button.close');
        if (closeBtn instanceof window.HTMLElement) {
          closeBtn.click();
        } else {
          activeTrap.dispatchEvent(new window.CustomEvent('dialog-close', { bubbles: true }));
        }
        if (previousActiveElement instanceof window.HTMLElement && previousActiveElement.isConnected) {
          previousActiveElement.focus({ preventScroll: true });
          previousActiveElement = null;
        }
        return;
      }
    }

    // 2. Roving tabindex navigation in containers (menus, toolbars, tablists)
    const targetElement = (document.activeElement && root.contains(document.activeElement) ? document.activeElement : null) || event.target;
    const rovingContainer = targetElement?.closest?.('[data-roving-tabindex]');
    if (rovingContainer && root.contains(rovingContainer)) {
      const orientation = rovingContainer.getAttribute('data-roving-tabindex') || 'horizontal';
      const isHorizontal = orientation === 'horizontal';
      const isNext = (isHorizontal && event.key === 'ArrowRight') || (!isHorizontal && event.key === 'ArrowDown');
      const isPrev = (isHorizontal && event.key === 'ArrowLeft') || (!isHorizontal && event.key === 'ArrowUp');
      const isHome = event.key === 'Home';
      const isEnd = event.key === 'End';

      if (isNext || isPrev || isHome || isEnd) {
        const items = Array.from(rovingContainer.querySelectorAll('[role="tab"], [role="menuitem"], button, [data-roving-item]'))
          .filter(el => el instanceof window.HTMLElement && !el.hidden && !el.hasAttribute('disabled') && !el.closest('[hidden]'));
        if (items.length > 0) {
          event.preventDefault();
          const currentIndex = items.indexOf(document.activeElement);
          let targetIndex = 0;
          if (isHome) {
            targetIndex = 0;
          } else if (isEnd) {
            targetIndex = items.length - 1;
          } else if (isNext) {
            targetIndex = currentIndex >= 0 ? (currentIndex + 1) % items.length : 0;
          } else if (isPrev) {
            targetIndex = currentIndex > 0 ? currentIndex - 1 : items.length - 1;
          }
          for (const item of items) {
            item.setAttribute('tabindex', '-1');
          }
          items[targetIndex].setAttribute('tabindex', '0');
          items[targetIndex].focus({ preventScroll: true });
          return;
        }
      }
    }

    // 3. Declarative hotkeys ([data-hotkey])
    const isTextEditing = (event.target instanceof window.HTMLInputElement && ['text', 'search', 'tel', 'url', 'password', 'email', 'number'].includes(event.target.type))
      || event.target instanceof window.HTMLTextAreaElement
      || event.target?.isContentEditable;

    const parts = [];
    if (event.ctrlKey || event.metaKey) parts.push('ctrl');
    if (event.altKey) parts.push('alt');
    if (event.shiftKey && event.key.length > 1) parts.push('shift');
    parts.push(event.key.toLowerCase());
    const combo = parts.join('+');

    if (!isTextEditing || event.ctrlKey || event.metaKey || event.altKey || event.key === 'Escape') {
      const candidates = Array.from(root.querySelectorAll('[data-hotkey]')).filter(el => {
        return el instanceof window.HTMLElement && !el.hidden && !el.closest('[hidden]') && !el.hasAttribute('disabled');
      });
      for (const candidate of candidates) {
        const declared = (candidate.getAttribute('data-hotkey') || '').toLowerCase().split(',').map(s => s.trim());
        if (declared.includes(combo)) {
          event.preventDefault();
          candidate.click();
          return;
        }
      }
    }
  }

  function handleFocusIn(event) {
    const target = event.target;
    if (!target) return;
    const activeTrap = root.querySelector('[data-trap-focus="true"], dialog[open]');
    if (activeTrap && !activeTrap.hidden && !activeTrap.closest('[hidden]')) {
      if (activeTrap.contains(target)) {
        if (!previousActiveElement && event.relatedTarget && root.contains(event.relatedTarget) && !activeTrap.contains(event.relatedTarget)) {
          previousActiveElement = event.relatedTarget;
        }
      }
    }
  }

  root.addEventListener('blur', handleControlBlur, { capture: true });
  root.addEventListener('input', handleControlInput, { capture: true });
  root.addEventListener('change', handleControlInput, { capture: true });
  root.addEventListener('keydown', handleKeyDown, { capture: true });
  root.addEventListener('focusin', handleFocusIn, { capture: true });

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
      applyFormStates(root);
      applyObservedSizes(root);
      applyIslandHydration(root);
      layoutElements.clear();
      registerLayoutElements(root);
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
    applyFormStates(root);
    applyObservedSizes(root);
    applyIslandHydration(root);
    layoutElements.clear();
    registerLayoutElements(root);
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
    captureFlipFirst();
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
            applyFormStates(child);
            applyObservedSizes(child);
            applyIslandHydration(child);
            registerLayoutElements(child);
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
        applyFormStates(target);
        applyObservedSizes(target);
        applyIslandHydration(target);
        registerLayoutElements(target);
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
        if (['marker-start', 'marker-mid', 'marker-end'].includes(attribute)) {
          if (!(target instanceof window.SVGElement) || !/^(?:none|url\(#[A-Za-z0-9_-]+\))$/.test(fields[3])) {
            throw new Error('Zig SVG marker patch requires a document-local fragment');
          }
        }
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
        if (attribute === "data-observe-size") applyObservedSizes(target);
        if (attribute === "data-trap-focus" && fields[3] === "true") {
          previousActiveElement = document.activeElement;
          const focusables = getFocusableElements(target);
          if (focusables.length > 0) {
            focusables[0].focus({ preventScroll: true });
          } else if (target instanceof window.HTMLElement) {
            target.setAttribute('tabindex', '-1');
            target.focus({ preventScroll: true });
          }
        }
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
        if (attribute === "data-trap-focus") {
          if (previousActiveElement instanceof window.HTMLElement && previousActiveElement.isConnected) {
            previousActiveElement.focus({ preventScroll: true });
            previousActiveElement = null;
          }
        }
      } else {
        throw new Error(`Unknown or malformed Zig patch operation: ${line}`);
      }
    }
    if (patchTextFocus?.isConnected && !patchTextFocus.closest('[hidden]')) {
      patchTextFocus.focus({ preventScroll: true });
      patchTextFocus.setSelectionRange(patchTextFocus.value.length, patchTextFocus.value.length);
    }
    patchTextFocus = null;
    playFlipTransitions();
  }

  function dispose() {
    root.removeEventListener('blur', handleControlBlur, { capture: true });
    root.removeEventListener('input', handleControlInput, { capture: true });
    root.removeEventListener('change', handleControlInput, { capture: true });
    root.removeEventListener('keydown', handleKeyDown, { capture: true });
    root.removeEventListener('focusin', handleFocusIn, { capture: true });
    if (resizeObserver) {
      resizeObserver.disconnect();
      resizeObserver = null;
      observedElements.clear();
    }
    if (intersectionObserver) {
      intersectionObserver.disconnect();
      intersectionObserver = null;
    }
    flipFirst.clear();
    layoutElements.clear();
    optimisticBuffer.clear();
    for (const [node] of exiting) abortExit(node);
    nodes.dispose();
  }

  return Object.freeze({
    initialize,
    hydrate,
    applyPatchStream,
    dispose,
    applyOptimistic,
    confirmOptimistic,
    rollbackOptimistic,
    animateLayout: playFlipTransitions,
  });
}

export function createFrameSyncHost({ root, origin: expectedOrigin = '*', port = null } = {}) {
  const dom = createDomHost({ root });
  const window = root.ownerDocument?.defaultView || globalThis.window;

  function handleMessage(event) {
    if (expectedOrigin && expectedOrigin !== '*' && event.origin !== expectedOrigin) {
      return;
    }
    const data = event.data;
    if (!data || typeof data !== 'object') return;
    if (data.type === 'zg:patch-stream') {
      const buffer = data.buffer;
      if (buffer instanceof ArrayBuffer || ArrayBuffer.isView(buffer) || typeof buffer === 'string') {
        dom.applyPatchStream(buffer);
      }
    } else if (data.type === 'zg:initialize') {
      dom.initialize(data.html, data.options);
    }
  }

  if (port) {
    port.onmessage = handleMessage;
    if (typeof port.start === 'function') port.start();
  } else if (window && typeof window.addEventListener === 'function') {
    window.addEventListener('message', handleMessage);
  }

  function dispose() {
    if (port) {
      port.onmessage = null;
      if (typeof port.close === 'function') port.close();
    } else if (window && typeof window.removeEventListener === 'function') {
      window.removeEventListener('message', handleMessage);
    }
    dom.dispose();
  }

  return Object.freeze({ dom, dispose });
}

if (typeof globalThis.window !== 'undefined' && typeof globalThis.window.customElements !== 'undefined' && !globalThis.window.customElements.get('zg-view')) {
  globalThis.window.customElements.define('zg-view', class ZgView extends globalThis.window.HTMLElement {
    constructor() {
      super();
      this._dom = null;
      this._shadowRoot = null;
    }

    connectedCallback() {
      const shadowAttr = this.getAttribute('shadow');
      const useShadow = shadowAttr === 'open' || shadowAttr === 'closed';
      const container = useShadow
        ? (this._shadowRoot || this.attachShadow({ mode: shadowAttr }))
        : this;
      this._shadowRoot = useShadow ? container : null;
      this._dom = createDomHost({ root: container });
      const initialHtml = this.getAttribute('data-html');
      if (initialHtml) {
        this._dom.initialize(initialHtml);
      }
    }

    disconnectedCallback() {
      this._dom?.dispose();
      this._dom = null;
    }

    initialize(html, options) {
      if (!this._dom) {
        this.connectedCallback();
      }
      return this._dom.initialize(html, options);
    }

    hydrate(html) {
      if (!this._dom) {
        this.connectedCallback();
      }
      return this._dom.hydrate(html);
    }

    applyPatchStream(stream) {
      return this._dom?.applyPatchStream(stream);
    }

    applyOptimistic(target, options) {
      return this._dom?.applyOptimistic(target, options);
    }

    confirmOptimistic(actionId) {
      return this._dom?.confirmOptimistic(actionId);
    }

    rollbackOptimistic(actionId) {
      return this._dom?.rollbackOptimistic(actionId);
    }

    animateLayout() {
      return this._dom?.animateLayout();
    }

    dispose() {
      this._dom?.dispose();
      this._dom = null;
    }
  });
}

