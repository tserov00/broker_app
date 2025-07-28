package com.example.broker_app.controller;

import com.example.broker_app.dto.PortfolioDto;
import com.example.broker_app.service.PortfolioService;
import jakarta.servlet.http.HttpSession;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

// PortfolioController.java
@RestController
@RequestMapping("/api/portfolio")
public class PortfolioController {

    @Autowired
    private PortfolioService portfolioService;

    @GetMapping
    public ResponseEntity<List<PortfolioDto>> getPortfolio(HttpSession session) {
        Integer accountId = (Integer) session.getAttribute("accountId");
        if (accountId == null) {
            return ResponseEntity.status(401).build();
        }
        List<PortfolioDto> list = portfolioService.getPortfolio(accountId);
        return ResponseEntity.ok(list);
    }
}


