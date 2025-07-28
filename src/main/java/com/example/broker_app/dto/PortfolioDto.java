package com.example.broker_app.dto;

import java.math.BigDecimal;

public class PortfolioDto {
    private Integer securityId;
    private String ticker;
    private int totalQuantity;
    private BigDecimal avgBuyPrice;
    private BigDecimal currentPrice;
    private String currencyCode;
    private BigDecimal unrealizedProfit;

    public String getTicker() { return ticker; }
    public void setTicker(String ticker) { this.ticker = ticker; }

    public int getTotalQuantity() { return totalQuantity; }
    public void setTotalQuantity(int totalQuantity) { this.totalQuantity = totalQuantity; }

    public BigDecimal getAvgBuyPrice() { return avgBuyPrice; }
    public void setAvgBuyPrice(BigDecimal avgBuyPrice) { this.avgBuyPrice = avgBuyPrice; }

    public BigDecimal getCurrentPrice() { return currentPrice; }
    public void setCurrentPrice(BigDecimal currentPrice) { this.currentPrice = currentPrice; }

    public String getCurrencyCode() { return currencyCode; }
    public void setCurrencyCode(String currencyCode) { this.currencyCode = currencyCode; }

    public BigDecimal getUnrealizedProfit() { return unrealizedProfit; }
    public void setUnrealizedProfit(BigDecimal unrealizedProfit) { this.unrealizedProfit = unrealizedProfit; }

    public Integer getSecurityId() {
        return securityId;
    }

    public void setSecurityId(Integer securityId) {
        this.securityId = securityId;
    }
}
