package com.example.broker_app.dto;

import java.math.BigDecimal;

public class AccountDto {
    private String currencyCode;
    private BigDecimal balance;
    private BigDecimal reservedAmount;

    public String getCurrencyCode() { return currencyCode; }
    public void setCurrencyCode(String currencyCode) { this.currencyCode = currencyCode; }

    public BigDecimal getBalance() { return balance; }
    public void setBalance(BigDecimal balance) { this.balance = balance; }

    public BigDecimal getReservedAmount() { return reservedAmount; }
    public void setReservedAmount(BigDecimal reservedAmount) { this.reservedAmount = reservedAmount; }
}
