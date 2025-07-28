package com.example.broker_app.service;

import com.example.broker_app.dto.PortfolioDto;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.util.List;

// PortfolioService.java
@Service
public class PortfolioService {

    @Autowired
    private JdbcTemplate jdbc;

    public List<PortfolioDto> getPortfolio(int customerAccountId) {
        String sql = """
        SELECT 
          sec.id                       AS securityId,    -- ← теперь возвращаем id
          sec.ticker                   AS ticker,
          v.total_quantity            AS totalQuantity,
          v.avg_buy_price             AS avgBuyPrice,
          v.last_price                AS currentPrice,
          c.code                      AS currencyCode,
          v.profit                    AS unrealizedProfit
        FROM unrealized_profit_by_security_view v
        JOIN securities sec ON v.security_id = sec.id
        JOIN currencies c ON sec.currency_id = c.id
        WHERE v.customer_account_id = ?
        """;
        return jdbc.query(sql,
                (rs, rn) -> {
                    PortfolioDto dto = new PortfolioDto();
                    dto.setSecurityId(rs.getInt("securityId"));
                    dto.setTicker(rs.getString("ticker"));
                    dto.setTotalQuantity(rs.getInt("totalQuantity"));
                    dto.setAvgBuyPrice(rs.getBigDecimal("avgBuyPrice"));
                    dto.setCurrentPrice(rs.getBigDecimal("currentPrice"));
                    dto.setCurrencyCode(rs.getString("currencyCode"));
                    dto.setUnrealizedProfit(rs.getBigDecimal("unrealizedProfit"));
                    return dto;
                },
                customerAccountId
        );
    }
}

