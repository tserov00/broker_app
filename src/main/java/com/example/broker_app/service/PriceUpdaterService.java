package com.example.broker_app.service;

import com.example.broker_app.dto.SecurityDao;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class PriceUpdaterService {
    private final SecurityDao dao;
    private final FinnhubService api;
    private final Logger log = LoggerFactory.getLogger(getClass());

    public PriceUpdaterService(SecurityDao dao, FinnhubService api) {
        this.dao = dao;
        this.api = api;
    }

    public void updateAllPrices() {
        List<String> tickers = dao.findAllTickers();
        for (String ticker : tickers) {
            try {
                Double price = api.getLastPrice(ticker);
                if (price != null && price > 0) {
                    int rows = dao.updateLastPriceByTicker(ticker, price);
                    log.info("Updated {} → {} ({} rows)", ticker, price, rows);
                } else {
                    log.warn("Skipping {} – неверная цена: {}", ticker, price);
                }
            } catch (Exception ex) {
                log.error("Error updating {}: {}", ticker, ex.getMessage());
            }
        }
    }
}
