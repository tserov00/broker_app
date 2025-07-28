package com.example.broker_app.controller;

import com.example.broker_app.dto.SecurityDto;
import com.example.broker_app.service.MarketService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/market")
public class MarketController {

    @Autowired
    private MarketService marketService;

    /**
     * GET /api/market/securities
     * Возвращает список всех бумаг на рынке.
     */
    @GetMapping("/securities")
    public ResponseEntity<List<SecurityDto>> getAllSecurities() {
        List<SecurityDto> list = marketService.listSecurities();
        return ResponseEntity.ok(list);
    }
}
