import assert from 'node:assert/strict'
import test from 'node:test'
import { LOG_KEEP, expiredPath, rotatePlan, shouldRotate } from '../lib/log-rotate.js'

test('未到上限不轮转', () => {
  assert.equal(shouldRotate(0), false)
  assert.equal(shouldRotate(9 * 1024 * 1024), false)
})

test('达到上限轮转', () => {
  assert.equal(shouldRotate(10 * 1024 * 1024), true)
  assert.equal(shouldRotate(11 * 1024 * 1024), true)
})

test('非法尺寸不轮转（避免 stat 失败把日志清空）', () => {
  assert.equal(shouldRotate(NaN), false)
  assert.equal(shouldRotate(undefined), false)
})

test('轮转计划从旧到新，最后才动当前文件', () => {
  const plan = rotatePlan('/tmp/x.log', 3)
  assert.deepEqual(plan, [
    { from: '/tmp/x.log.2', to: '/tmp/x.log.3' },
    { from: '/tmp/x.log.1', to: '/tmp/x.log.2' },
    { from: '/tmp/x.log', to: '/tmp/x.log.1' },
  ])
})

test('保留份数可配置', () => {
  const plan = rotatePlan('/tmp/x.log', 1)
  assert.deepEqual(plan, [{ from: '/tmp/x.log', to: '/tmp/x.log.1' }])
})

test('最老一份的路径', () => {
  assert.equal(expiredPath('/tmp/x.log'), `/tmp/x.log.${LOG_KEEP + 1}`)
})
