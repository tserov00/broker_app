package com.example.broker_app.dto;

import java.math.BigDecimal;

public class BuyOrderRequest {
    private Integer securityId;
    private BigDecimal price;
    private Integer quantity;

    public Integer getSecurityId() { return securityId; }
    public void setSecurityId(Integer securityId) { this.securityId = securityId; }

    public BigDecimal getPrice() { return price; }
    public void setPrice(BigDecimal price) { this.price = price; }

    public Integer getQuantity() { return quantity; }
    public void setQuantity(Integer quantity) { this.quantity = quantity; }
}
