package com.example.broker_app.controller;

import com.example.broker_app.dto.BuyOrderRequest;
import com.example.broker_app.dto.OrderDto;
import com.example.broker_app.dto.SellOrderRequest;
import com.example.broker_app.service.OrderService;
import jakarta.servlet.http.HttpSession;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/orders")
public class OrderController {

    @Autowired
    private OrderService orderService;

    /**
     * POST /api/orders/buy
     * Тело JSON { securityId, price, quantity }
     */
    @PostMapping("/buy")
    public ResponseEntity<String> buy(
            @RequestBody BuyOrderRequest rq,
            HttpSession session
    ) {
        Integer accountId = (Integer) session.getAttribute("accountId");
        if (accountId == null) {
            return ResponseEntity.status(401).body("Неавторизован");
        }

        try {
            orderService.createBuyOrder(accountId, rq);
            return ResponseEntity.ok("Order created");
        } catch (Exception ex) {
            // логируем ex
            return ResponseEntity
                    .status(500)
                    .body("Ошибка при создании ордера: " + ex.getMessage());
        }
    }

    @PostMapping("/sell")
    public ResponseEntity<String> sell(
            @RequestBody SellOrderRequest rq,
            HttpSession session
    ) {
        Integer accountId = (Integer) session.getAttribute("accountId");
        if (accountId == null) {
            return ResponseEntity.status(401).body("Неавторизован");
        }
        try {
            orderService.createSellOrder(accountId, rq);
            return ResponseEntity.ok("Sell order created");
        } catch (Exception ex) {
            return ResponseEntity
                    .status(500)
                    .body("Ошибка при создании Sell-ордера: " + ex.getMessage());
        }
    }

    @GetMapping("/history")
    public ResponseEntity<List<OrderDto>> history(HttpSession session) {
        Integer accountId = (Integer) session.getAttribute("accountId");
        if (accountId == null) {
            return ResponseEntity.status(401).build();
        }
        List<OrderDto> list = orderService.listOrders(accountId);
        return ResponseEntity.ok(list);
    }
}
