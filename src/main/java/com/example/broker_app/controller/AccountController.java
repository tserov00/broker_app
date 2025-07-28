package com.example.broker_app.controller;

import com.example.broker_app.dto.AccountDto;
import com.example.broker_app.dto.BalanceHistoryDto;
import com.example.broker_app.dto.OperationRequest;
import com.example.broker_app.service.AccountService;
import jakarta.servlet.http.HttpSession;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/accounts")
public class AccountController {

    @Autowired
    private AccountService accountService;

    /**
     * GET /api/accounts/list
     */
    @GetMapping("/list")
    public ResponseEntity<List<AccountDto>> list(HttpSession session) {
        Integer accountId = (Integer) session.getAttribute("accountId");
        if (accountId == null) {
            return ResponseEntity.status(401).build();
        }
        var list = accountService.listAccounts(accountId);
        return ResponseEntity.ok(list);
    }

    /**
     * POST /api/accounts/deposit
     * body: { currencyCode, amount }
     */
    @PostMapping("/deposit")
    public ResponseEntity<String> deposit(
            @RequestBody OperationRequest rq,
            HttpSession session
    ) {
        Integer accountId = (Integer) session.getAttribute("accountId");
        if (accountId == null) {
            return ResponseEntity.status(401).body("Неавторизован");
        }
        try {
            accountService.deposit(rq, accountId);
            return ResponseEntity.ok("OK");
        } catch (Exception ex) {
            return ResponseEntity.status(400).body("Ошибка депозита: " + ex.getMessage());
        }
    }

    /**
     * POST /api/accounts/withdraw
     * body: { currencyCode, amount }
     */
    @PostMapping("/withdraw")
    public ResponseEntity<String> withdraw(
            @RequestBody OperationRequest rq,
            HttpSession session
    ) {
        Integer accountId = (Integer) session.getAttribute("accountId");
        if (accountId == null) {
            return ResponseEntity.status(401).body("Неавторизован");
        }
        try {
            accountService.withdraw(rq, accountId);
            return ResponseEntity.ok("OK");
        } catch (Exception ex) {
            return ResponseEntity.status(400).body("Ошибка вывода: " + ex.getMessage());
        }
    }

    @GetMapping("/history")
    public ResponseEntity<List<BalanceHistoryDto>> history(HttpSession session) {
        Integer accountId = (Integer) session.getAttribute("accountId");
        if (accountId == null) {
            return ResponseEntity.status(401).build();
        }
        List<BalanceHistoryDto> history = accountService.getBalanceHistory(accountId);
        return ResponseEntity.ok(history);
    }
}

