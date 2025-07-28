package com.example.broker_app.dto;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public class SecurityDao {
    private final JdbcTemplate jdbc;

    public SecurityDao(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<String> findAllTickers() {
        String sql = "SELECT ticker FROM securities WHERE ticker IS NOT NULL";
        return jdbc.query(sql, (rs, rowNum) -> rs.getString("ticker"));
    }

    public int updateLastPriceByTicker(String ticker, Double price) {
        String sql = "UPDATE securities SET last_price = ?, updated_at = now() WHERE ticker = ?";
        return jdbc.update(sql, price, ticker);
    }
}
