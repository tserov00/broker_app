package com.example.broker_app.controller;

import com.example.broker_app.service.AuthService;
import jakarta.servlet.http.HttpSession;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/auth")
public class AuthController {

    @Autowired
    private AuthService authService;

    @PostMapping("/login")
    public ResponseEntity<String> login(
            @RequestParam String login,
            @RequestParam String password,
            HttpSession session
    ) {
        Integer accountId = authService.authenticateAndGetAccountId(login, password);
        if (accountId == null) {
            return ResponseEntity.status(401).body("Invalid login or password");
        }
        session.setAttribute("accountId", accountId);
        return ResponseEntity.ok("AUTH_OK");
    }

    @PostMapping("/logout")
    public ResponseEntity<Void> logout(HttpSession session) {
        session.invalidate();
        return ResponseEntity.ok().build();
    }
}

