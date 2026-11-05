/**
 * When an order's quantity has come off its listing. An order takes its
 * stock when the farmer confirms it (the app stamps stockDeductedAt in the
 * same transaction); an order placed before that rule — it has no
 * stockOnConfirm — took its stock when it was placed. So a cancelled or
 * turned-away order gives stock back only when this is true. The same
 * rule as orderTookStock in lib/services/order_service.dart. Pure, so it
 * is tested without Firebase.
 */
function stockWasTaken(order) {
  if (!order) return false;
  return order.stockOnConfirm !== true || !!order.stockDeductedAt;
}

/**
 * What the farmer is told when [order] is cancelled by someone else, and
 * whether its quantity went back on the listing ([returned]).
 */
function cancelledNoticeForFarmer(order, { returned, pendingDays }) {
  const product = order.productName || "product";
  const buyer = order.buyerName || "The buyer";
  const back = returned ? " The quantity is back on your listing." : "";
  if (order.cancelReason === "expired") {
    return `The ${product} order from ${buyer} was cancelled because it was not answered within ${pendingDays} days.${back}`;
  }
  if (order.cancelReason === "buyer") {
    return `${buyer} cancelled the ${product} order.${back}`;
  }
  return `${buyer} cancelled the ${product} order after the delay.${back}`;
}

module.exports = { stockWasTaken, cancelledNoticeForFarmer };
