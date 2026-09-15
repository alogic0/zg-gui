import { localDatetime, localTimeLabel, applyInitialTimeFormats } from './local-datetime.js';

// Only this module writes the DOM after initialization. Hooks bind host-owned
// capabilities to explicitly introduced subtrees; they do not choose UI state.
export function createDomHost({ root, onStructure = () => {} }) {
  const document = root.ownerDocument;
  const window = document.defaultView;
  let patchTextFocus = null;
  function patchNode(nodeId) {
    if (!/^\d+$/.test(nodeId)) throw new Error(`Invalid Zig patch node id: ${nodeId}`);
    const nodes = root.querySelectorAll(`[data-node-id="${nodeId}"]`);
    if (nodes.length !== 1) {
      throw new Error(`Zig patch node ${nodeId} resolved to ${nodes.length} elements`);
    }
    return nodes[0];
  }

  // Attribute names Zig is allowed to set through the A/R operations. Names
  // are Zig literals, so this is defense in depth: an unexpected name fails
  // the stream (and resyncs) instead of reaching setAttribute.
  const attributePattern = /^(?:viewBox|d|fill|stroke|stroke-width|x|y|x1|x2|y1|y2|cx|cy|r|rx|ry|width|height|points|transform|id|for|class|lang|hidden|disabled|readonly|datetime|draggable|inert|role|title|href|src|alt|type|name|placeholder|autofocus|autocomplete|min|max|step|minlength|maxlength|aria-[a-z]+(?:-[a-z]+)*|data-[a-z]+(?:-[a-z]+)*)$/;

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
    const nodes = scope.matches?.('select[data-select-value]') ? [scope] : [];
    nodes.push(...scope.querySelectorAll('select[data-select-value]'));
    const parent = scope.closest?.('select[data-select-value]');
    if (parent && !nodes.includes(parent)) nodes.push(parent);
    for (const select of nodes) select.value = select.dataset.selectValue;
  }
  function applyDeclaredProviders(scope) { onStructure(scope); }

  function initialize(html) {
    root.innerHTML = html;
    applySelectValues(root);
    applyDeclaredStyles(root);
    applyInitialTimeFormats(root);
    onStructure(root);
  }

  function applyPatchStream(stream) {
    patchTextFocus = null;
    for (const line of stream.split("\n")) {
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
        target.remove();
        applySelectValues(parent);
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
          target.value = target.dataset.valueFormat === 'instant-local' ? localDatetime(fragment) : fragment;
          continue;
        }
        if (operation === "T") {
          target.textContent = localTimeLabel(fragment, { format: target.dataset.textFormat || 'plain' });
          continue;
        }
        if (operation === "J") {
          if (!(target instanceof window.HTMLElement) && !(target instanceof window.SVGElement)) throw new Error("Zig append patch needs an HTML or SVG element");
          const last = target.lastElementChild;
          target.insertAdjacentHTML("beforeend", fragment);
          applySelectValues(target);
          for (let child = last ? last.nextElementSibling : target.firstElementChild; child; child = child.nextElementSibling) {
            applyDeclaredStyles(child);
            applyDeclaredProviders(child);
            applyInitialTimeFormats(child);
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
        target.innerHTML = fragment;
        applySelectValues(target);
        applyDeclaredStyles(target);
        applyDeclaredProviders(target);
        applyInitialTimeFormats(target);
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
          const allowed = url.origin === window.location.origin || target.getAttribute?.('data-external-image') === 'true';
          if (!(target instanceof window.HTMLImageElement) || !allowed
            || !['http:', 'https:'].includes(url.protocol) || url.username || url.password) {
            throw new Error("Zig image source patch requires a same-origin image or an explicit HTTP(S) image permission");
          }
        }
        target.setAttribute(attribute, fields[3]);
        if (attribute === "data-select-value" || (attribute === "value" && target instanceof window.HTMLOptionElement)) applySelectValues(target);
        if (attribute === "data-style-vars") applyDeclaredStyles(target);
      } else if (operation === "R" && fields.length === 3) {
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

  return Object.freeze({ initialize, applyPatchStream });
}
