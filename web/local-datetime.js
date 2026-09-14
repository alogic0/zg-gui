// Environment formatting only. Zig owns canonical instants and validation.
export function localDatetime(value) {
  if (!value) return '';
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) return '';
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, -1);
}
export function instantFromLocal(value) {
  if (!value) return '';
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,3})?)?$/.test(value)) return 'invalid-local-time';
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) return 'invalid-local-time';
  // Refuse nonexistent wall times instead of silently moving them across a gap.
  const canonical = value.length === 16 ? `${value}:00.000` : value.includes('.') ? value.padEnd(23, '0') : `${value}.000`;
  if (localDatetime(date.toISOString()) !== canonical) return 'invalid-local-time';
  return date.toISOString();
}
export function localTimeLabel(value, { format = 'instant-local' } = {}) {
  if (!['instant-local', 'instant-local-date'].includes(format)) return value;
  const date = new Date(value);
  if (!value || !Number.isFinite(date.getTime())) return format === 'instant-local-date' ? 'n/a' : value;
  const two = number => String(number).padStart(2, '0');
  const day = `${two(date.getMonth() + 1)}/${two(date.getDate())}`;
  const year = format === 'instant-local-date' ? `/${date.getFullYear()}` : '';
  return `${day}${year}, ${two(date.getHours() % 12 || 12)}:${two(date.getMinutes())} ${date.getHours() >= 12 ? 'PM' : 'AM'}`;
}
export function declaredInputValue(input) {
  const value = input.dataset.valueFormat === 'checked' ? String(input.checked) : String(input.value || '');
  return (input.dataset.inputPrefix || '') + (input.dataset.valueFormat === 'instant-local' ? instantFromLocal(value) : value);
}
export function applyInitialTimeFormats(scope) {
  const nodes = selector => [...(scope.matches?.(selector) ? [scope] : []), ...scope.querySelectorAll(selector)];
  for (const input of nodes('[data-value-format="instant-local"]')) input.value = localDatetime(input.dataset.initialValue);
  for (const node of nodes('[data-text-format]')) node.textContent = localTimeLabel(node.textContent, { format: node.dataset.textFormat });
}
