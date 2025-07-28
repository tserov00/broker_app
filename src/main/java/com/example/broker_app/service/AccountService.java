package com.example.broker_app.service;

import com.example.broker_app.dto.AccountDto;
import com.example.broker_app.dto.BalanceHistoryDto;
import com.example.broker_app.dto.OperationRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.util.List;

// AccountService.java
@Service
public class AccountService {

    @Autowired
    private JdbcTemplate jdbc;

    public List<AccountDto> listAccounts(int customerAccountId) {
        String sql = """
            SELECT c.code               AS currencyCode,
                   sa.balance           AS balance,
                   sa.reserved_amount   AS reservedAmount
            FROM savings_accounts sa
            JOIN currencies c ON sa.currency_id = c.id
            WHERE sa.customer_account_id = ?
            """;
        return jdbc.query(sql,
                (rs, rn) -> {
                    AccountDto dto = new AccountDto();
                    dto.setCurrencyCode(rs.getString("currencyCode"));
                    dto.setBalance(rs.getBigDecimal("balance"));
                    dto.setReservedAmount(rs.getBigDecimal("reservedAmount"));
                    return dto;
                },
                customerAccountId
        );
    }

    public void deposit(OperationRequest rq, int customerAccountId) {
        Integer currencyId = jdbc.queryForObject(
                "SELECT id FROM currencies WHERE code = ?",
                Integer.class,
                rq.getCurrencyCode()
        );

        Integer saId;
        try {
            saId = jdbc.queryForObject(
                    "SELECT id FROM savings_accounts WHERE customer_account_id = ? AND currency_id = ?",
                    Integer.class,
                    customerAccountId, currencyId
            );
        } catch (EmptyResultDataAccessException ex) {
            String accountNumber = jdbc.queryForObject(
                    "SELECT generate_savings_account_number()",
                    String.class
            );
            jdbc.update(
                    "INSERT INTO savings_accounts(customer_account_id, savings_account_number, currency_id, balance, reserved_amount) " +
                            "VALUES (?, ?, ?, 0.00, 0.00)",
                    customerAccountId, accountNumber, currencyId
            );
            saId = jdbc.queryForObject(
                    "SELECT id FROM savings_accounts WHERE customer_account_id = ? AND currency_id = ?",
                    Integer.class,
                    customerAccountId, currencyId
            );
        }

        jdbc.update("CALL deposit_balance(?, ?)", rq.getAmount(), saId);
    }

    public void withdraw(OperationRequest rq, int customerAccountId) {
        Integer currencyId = jdbc.queryForObject(
                "SELECT id FROM currencies WHERE code = ?",
                Integer.class,
                rq.getCurrencyCode()
        );
        Integer saId = jdbc.queryForObject(
                "SELECT id FROM savings_accounts WHERE customer_account_id = ? AND currency_id = ?",
                Integer.class,
                customerAccountId, currencyId
        );
        jdbc.update("CALL withdraw_balance(?, ?)", rq.getAmount(), saId);
    }
    public List<BalanceHistoryDto> getBalanceHistory(int customerAccountId) {
        String sql = """
            SELECT 
              bh.amount                     AS amount,
              tt.transaction_type           AS transactionType,
              bh.transaction_date           AS transactionDate,
              c.code                        AS currencyCode
            FROM balance_history bh
            JOIN transaction_types tt
              ON bh.transaction_type = tt.id
            JOIN savings_accounts sa
              ON bh.savings_account_id = sa.id
            JOIN currencies c
              ON sa.currency_id = c.id
            WHERE sa.customer_account_id = ?
            ORDER BY bh.transaction_date DESC
            """;
        return jdbc.query(sql,
                (rs, rn) -> {
                    BalanceHistoryDto dto = new BalanceHistoryDto();
                    dto.setAmount(rs.getBigDecimal("amount"));
                    dto.setTransactionType(rs.getString("transactionType"));
                    dto.setTransactionDate(
                            rs.getObject("transactionDate", java.time.OffsetDateTime.class)
                    );
                    dto.setCurrencyCode(rs.getString("currencyCode"));
                    return dto;
                },
                customerAccountId
        );
    }
}
