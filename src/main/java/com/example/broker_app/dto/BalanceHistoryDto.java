package com.example.broker_app.dto;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

public class BalanceHistoryDto {
    private BigDecimal amount;
    private String transactionType; // "DEPOSIT" или "WITHDRAW"
    private OffsetDateTime transactionDate;
    private String currencyCode;    // ← новое поле

    public BigDecimal getAmount() { return amount; }
    public void setAmount(BigDecimal amount) { this.amount = amount; }

    public String getTransactionType() { return transactionType; }
    public void setTransactionType(String transactionType) { this.transactionType = transactionType; }

    public OffsetDateTime getTransactionDate() { return transactionDate; }
    public void setTransactionDate(OffsetDateTime transactionDate) { this.transactionDate = transactionDate; }

    public String getCurrencyCode() { return currencyCode; }
    public void setCurrencyCode(String currencyCode) { this.currencyCode = currencyCode; }
}

