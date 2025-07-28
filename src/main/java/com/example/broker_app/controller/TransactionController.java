package com.example.broker_app.controller;

import com.example.broker_app.dto.TransactionDto;
import com.example.broker_app.service.TransactionService;
import jakarta.servlet.http.HttpSession;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/transactions")
public class TransactionController {

    @Autowired
    private TransactionService transactionService;

    /**
     * GET /api/transactions
     */
    @GetMapping
    public ResponseEntity<List<TransactionDto>> getTransactions(HttpSession session) {
        Integer accountId = (Integer) session.getAttribute("accountId");
        if (accountId == null) {
            return ResponseEntity.status(401).build();
        }
        List<TransactionDto> list = transactionService.listTransactions(accountId);
        return ResponseEntity.ok(list);
    }
}
