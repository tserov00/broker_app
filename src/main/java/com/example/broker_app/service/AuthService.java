package com.example.broker_app.service;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.util.Map;

@Service
public class AuthService {

    @Autowired
    private JdbcTemplate jdbc;

    public Integer authenticateAndGetAccountId(String login, String rawPassword) {
        try {
            Map<String,Object> row = jdbc.queryForMap(
                    "SELECT id, password_hash FROM customer_accounts WHERE login = ?",
                    login
            );
            String storedHash = (String)row.get("password_hash");
            String hashed = Integer.toHexString(rawPassword.hashCode());
            if (!hashed.equals(storedHash)) return null;
            return (Integer)row.get("id");
        } catch (EmptyResultDataAccessException ex) {
            return null;
        }
    }
}
