import assert from 'node:assert/strict';
import { test } from 'node:test';
import { localDatetime, instantFromLocal, localTimeLabel } from '../web/local-datetime.js';

test('canonical instants round trip local formatting', () => {
  const instant = '2026-09-14T12:34:56.123Z';
  assert.equal(instantFromLocal(localDatetime(instant)), instant);
  assert.equal(instantFromLocal('not a date'), 'invalid-local-time');
  assert.equal(localTimeLabel('<plain>', { format: 'plain' }), '<plain>');
});
