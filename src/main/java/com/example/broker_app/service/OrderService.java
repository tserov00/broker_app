package com.example.broker_app.service;

import com.example.broker_app.dto.BuyOrderRequest;
import com.example.broker_app.dto.OrderDto;
import com.example.broker_app.dto.SellOrderRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class OrderService {

    @Autowired
    private JdbcTemplate jdbc;

    public void createBuyOrder(int customerAccountId, BuyOrderRequest rq) {
        // 1. Узнаём currency_id для этой бумаги
        Integer currencyId = jdbc.queryForObject(
                "SELECT currency_id FROM securities WHERE id = ?",
                Integer.class,
                rq.getSecurityId()
        );

        // 2. Находим соответствующий savings_account_id
        Integer savingsAccountId;
        try {
            savingsAccountId = jdbc.queryForObject(
                    "SELECT id FROM savings_accounts WHERE customer_account_id = ? AND currency_id = ?",
                    Integer.class,
                    customerAccountId, currencyId
            );
        } catch (EmptyResultDataAccessException ex) {
            throw new IllegalStateException(
                    "У вас нет счёта в валюте бумаги (currency_id=" + currencyId + ")"
            );
        }

        jdbc.update(
                "CALL create_buy_order(?, ?, ?, ?)",
                rq.getSecurityId(),
                rq.getPrice(),
                rq.getQuantity(),
                savingsAccountId
        );
    }

    public void createSellOrder(int customerAccountId, SellOrderRequest rq) {
        Integer currencyId = jdbc.queryForObject(
                "SELECT currency_id FROM securities WHERE id = ?",
                Integer.class,
                rq.getSecurityId()
        );

        Integer savingsAccountId;
        try {
            savingsAccountId = jdbc.queryForObject(
                    "SELECT id FROM savings_accounts WHERE customer_account_id = ? AND currency_id = ?",
                    Integer.class,
                    customerAccountId, currencyId
            );
        } catch (EmptyResultDataAccessException ex) {
            throw new IllegalStateException("У вас нет счёта в валюте бумаги (currency_id=" + currencyId + ")");
        }

        jdbc.update(
                "CALL create_sell_order(?, ?, ?, ?)",
                rq.getSecurityId(),
                rq.getPrice(),
                rq.getQuantity(),
                savingsAccountId
        );
    }

    public List<OrderDto> listOrders(int customerAccountId) {
        String sql = """
        SELECT 
          o.id                                    AS id,
          s.ticker                                AS ticker,
          ot.type                                 AS orderType,
          o.price                                 AS price,
          o.fee                                   AS fee,
          o.quantity                              AS quantity,
          o.available_quantity                    AS availableQuantity,
          os.status                               AS status,
          o.created_at                            AS createdAt,
          s.last_price                            AS currentPrice
        FROM orders o
        JOIN securities s     ON o.security_id = s.id
        JOIN order_type ot    ON o.order_type_id = ot.id
        JOIN order_status os  ON o.order_status_id = os.id
        WHERE o.customer_account_id = ?
        ORDER BY o.created_at DESC
        """;

        return jdbc.query(sql,
                (rs, rowNum) -> {
                    OrderDto dto = new OrderDto();
                    dto.setId(rs.getInt("id"));
                    dto.setTicker(rs.getString("ticker"));
                    dto.setOrderType(rs.getString("orderType"));
                    dto.setPrice(rs.getBigDecimal("price"));
                    dto.setFee(rs.getBigDecimal("fee"));
                    dto.setQuantity(rs.getInt("quantity"));
                    dto.setAvailableQuantity(rs.getInt("availableQuantity"));
                    dto.setStatus(rs.getString("status"));
                    dto.setCreatedAt(rs.getObject("createdAt", java.time.OffsetDateTime.class));
                    dto.setCurrentPrice(rs.getBigDecimal("currentPrice"));
                    return dto;
                },
                customerAccountId
        );
    }
}
