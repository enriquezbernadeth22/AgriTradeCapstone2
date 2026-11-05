// An order takes its stock when the farmer confirms it; only then does a
// cancellation give stock back. Orders from before this rule took it when
// placed, and still get it back.
const test = require("node:test");
const assert = require("node:assert");
const { stockWasTaken, cancelledNoticeForFarmer } = require("../order_stock_logic");

test("a pending order has taken no stock", () => {
  assert.strictEqual(stockWasTaken({ stockOnConfirm: true, status: "pending" }), false);
});

test("a confirmed order has taken its stock", () => {
  assert.strictEqual(
    stockWasTaken({ stockOnConfirm: true, stockDeductedAt: { seconds: 1 } }),
    true,
  );
});

test("an order from before the rule took its stock when placed", () => {
  assert.strictEqual(stockWasTaken({ status: "pending" }), true);
});

test("nothing to give back for no order", () => {
  assert.strictEqual(stockWasTaken(null), false);
});

test("the farmer is told the quantity is back only when it is", () => {
  const order = { productName: "Corn", buyerName: "Ana", cancelReason: "buyer" };
  assert.strictEqual(
    cancelledNoticeForFarmer(order, { returned: false, pendingDays: 3 }),
    "Ana cancelled the Corn order.",
  );
  assert.strictEqual(
    cancelledNoticeForFarmer(order, { returned: true, pendingDays: 3 }),
    "Ana cancelled the Corn order. The quantity is back on your listing.",
  );
  assert.match(
    cancelledNoticeForFarmer({ ...order, cancelReason: "expired" }, { returned: false, pendingDays: 3 }),
    /not answered within 3 days\.$/,
  );
  assert.match(
    cancelledNoticeForFarmer({ ...order, cancelReason: "delay" }, { returned: true, pendingDays: 3 }),
    /after the delay\. The quantity is back on your listing\.$/,
  );
});
