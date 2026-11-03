/**
 * The fields of a market_sales record that come from its order, shared by
 * recordMarketSale and backfill_market_sales.js. Pure functions, so they are
 * tested without Firebase.
 */

/**
 * The buyer's general area for a sale: the one saved on the order at
 * checkout, so a sale stays where it was made if the buyer later moves.
 * The buyer's profile only fills in for an order placed before it was saved.
 */
function saleBuyerArea(order, profileMunicipality) {
  const frozen = typeof order.buyerMunicipality === "string" ? order.buyerMunicipality.trim() : "";
  if (frozen) return frozen;
  return typeof profileMunicipality === "string" ? profileMunicipality.trim() : "";
}

/**
 * The price paid per unit, which the Add Product price recommendation reads
 * (a farmer cannot read other farmers' orders). Null when the order has none.
 */
function salePricePerUnit(order) {
  const price = Number(order.pricePerUnit ?? order.unitPrice);
  return Number.isFinite(price) && price > 0 ? price : null;
}

module.exports = { saleBuyerArea, salePricePerUnit };
