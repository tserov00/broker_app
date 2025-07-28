package com.example.broker_app.dto;

import java.math.BigDecimal;

public class TransactionDto {
    private String ticker;
    private String transactionType;
    private BigDecimal executedPrice;
    private BigDecimal executedFee;
    private Integer quantity;
    private Integer orderId;

    public String getTicker() { return ticker; }
    public void setTicker(String ticker) { this.ticker = ticker; }

    public String getTransactionType() { return transactionType; }
    public void setTransactionType(String transactionType) { this.transactionType = transactionType; }

    public BigDecimal getExecutedPrice() { return executedPrice; }
    public void setExecutedPrice(BigDecimal executedPrice) { this.executedPrice = executedPrice; }

    public BigDecimal getExecutedFee() { return executedFee; }
    public void setExecutedFee(BigDecimal executedFee) { this.executedFee = executedFee; }

    public Integer getQuantity() { return quantity; }
    public void setQuantity(Integer quantity) { this.quantity = quantity; }

    public Integer getOrderId() { return orderId; }
    public void setOrderId(Integer orderId) { this.orderId = orderId; }
}
