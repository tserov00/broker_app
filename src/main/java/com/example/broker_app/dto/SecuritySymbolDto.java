package com.example.broker_app.dto;

public class SecuritySymbolDto {
    private final String finnhubSymbol;
    private final String ticker;

    public SecuritySymbolDto(String finnhubSymbol, String ticker) {
        this.finnhubSymbol = finnhubSymbol;
        this.ticker = ticker;
    }
    public String getFinnhubSymbol() { return finnhubSymbol; }
    public String getTicker()       { return ticker; }
}
