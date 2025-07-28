package com.example.broker_app.controller;

import jakarta.servlet.http.HttpSession;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.sql.Date;
import java.util.Map;
import java.util.UUID;

@RestController
public class RegistrationController {

    @Autowired
    private JdbcTemplate jdbc;

    @PostMapping("/register")
    @Transactional
    public String register(@RequestParam Map<String,String> f,
                           HttpSession session) {
        Integer custId = jdbc.queryForObject(
                "INSERT INTO customers(first_name, last_name, date_of_birth, passport_series, address, tax_id) " +
                        "VALUES (?,?,?,?,?,?) RETURNING id",
                Integer.class,
                f.get("firstName"),
                f.get("lastName"),
                Date.valueOf(f.get("birthDate")),
                f.get("passport"),
                f.get("address"),
                f.get("inn")
        );

        String passHash = Integer.toHexString(f.get("password").hashCode());
        Integer accId = jdbc.queryForObject(
                "INSERT INTO customer_accounts(customer_id, phone_number, email, login, password_hash) " +
                        "VALUES (?,?,?,?,?) RETURNING id",
                Integer.class,
                custId,
                f.get("phone"),
                f.get("email"),
                f.get("login"),
                passHash
        );

        String accNum = "SA-" + UUID.randomUUID();
        jdbc.update(
                "INSERT INTO savings_accounts(customer_account_id, savings_account_number, currency_id, balance, reserved_amount) " +
                        "VALUES (?, generate_savings_account_number(), 1, 0.00, 0.00)",
                accId
        );

        session.setAttribute("accountId", accId);

        return "redirect:/portfolio.html";
    }
}
