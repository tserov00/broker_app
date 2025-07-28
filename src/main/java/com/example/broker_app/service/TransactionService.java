package com.example.broker_app.service;

import com.example.broker_app.dto.TransactionDto;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class TransactionService {

    @Autowired
    private JdbcTemplate jdbc;

    public List<TransactionDto> listTransactions(int accountId) {
        String sql = """
            SELECT s.ticker             AS ticker,
                   'BUY'                AS transactionType,
                   t.executed_price     AS executedPrice,
                   t.executed_fee       AS executedFee,
                   t.quantity           AS quantity,
                   t.buy_order_id       AS orderId
            FROM transactions t
            JOIN orders bo ON t.buy_order_id = bo.id
            JOIN securities s ON bo.security_id = s.id
            WHERE bo.customer_account_id = ?

            UNION ALL

            SELECT s.ticker             AS ticker,
                   'SELL'               AS transactionType,
                   t.executed_price     AS executedPrice,
                   t.executed_fee       AS executedFee,
                   t.quantity           AS quantity,
                   t.sell_order_id      AS orderId
            FROM transactions t
            JOIN orders so ON t.sell_order_id = so.id
            JOIN securities s ON so.security_id = s.id
            WHERE so.customer_account_id = ?

            ORDER BY orderId DESC
            """;

        return jdbc.query(sql,
                (rs, rowNum) -> {
                    TransactionDto dto = new TransactionDto();
                    dto.setTicker(rs.getString("ticker"));
                    dto.setTransactionType(rs.getString("transactionType"));
                    dto.setExecutedPrice(rs.getBigDecimal("executedPrice"));
                    dto.setExecutedFee(rs.getBigDecimal("executedFee"));
                    dto.setQuantity(rs.getInt("quantity"));
                    dto.setOrderId(rs.getInt("orderId"));
                    return dto;
                },
                accountId, accountId
        );
    }
}

