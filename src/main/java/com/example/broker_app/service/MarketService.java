package com.example.broker_app.service;

import com.example.broker_app.dto.SecurityDto;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class MarketService {

    @Autowired
    private JdbcTemplate jdbc;

    public List<SecurityDto> listSecurities() {
        String sql = """
          SELECT 
            s.id                  AS id,           -- ← теперь выбираем id
            s.ticker              AS ticker,
            s.company_name        AS companyName,
            s.isin                AS isin,
            c.code                AS currencyCode,
            s.last_price          AS lastPrice
          FROM securities s
          JOIN currencies c ON s.currency_id = c.id
          ORDER BY s.ticker
          """;
        return jdbc.query(sql,
                (rs, rowNum) -> {
                    SecurityDto dto = new SecurityDto();
                    dto.setId(rs.getInt("id"));                 // ← сохраняем id
                    dto.setTicker(rs.getString("ticker"));
                    dto.setCompanyName(rs.getString("companyName"));
                    dto.setIsin(rs.getString("isin"));
                    dto.setCurrencyCode(rs.getString("currencyCode"));
                    dto.setLastPrice(rs.getBigDecimal("lastPrice"));
                    return dto;
                }
        );
    }
}