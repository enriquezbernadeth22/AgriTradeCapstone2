// Run with: npm test   (from the functions folder)
const test = require("node:test");
const assert = require("node:assert");
const { saleBuyerArea, salePricePerUnit } = require("../market_sale_logic");

test("a sale stays in the area saved on the order", () => {
  assert.strictEqual(saleBuyerArea({ buyerMunicipality: " Laurel " }, "Talisay"), "Laurel");
});

test("an older order falls back to the buyer's profile", () => {
  assert.strictEqual(saleBuyerArea({}, " Talisay "), "Talisay");
  assert.strictEqual(saleBuyerArea({ buyerMunicipality: "" }, "Talisay"), "Talisay");
});

test("with no area on record it stays empty, never guessed", () => {
  assert.strictEqual(saleBuyerArea({}, null), "");
});

test("the price paid per unit is kept for the price recommendation", () => {
  assert.strictEqual(salePricePerUnit({ pricePerUnit: 42.5 }), 42.5);
  assert.strictEqual(salePricePerUnit({ unitPrice: "40" }), 40);
  assert.strictEqual(salePricePerUnit({}), null);
  assert.strictEqual(salePricePerUnit({ pricePerUnit: 0 }), null);
});
