package com.example.broker_app.scheduler;

import com.example.broker_app.service.PriceUpdaterService;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
@EnableScheduling
public class PriceScheduler {
    private final PriceUpdaterService updater;

    public PriceScheduler(PriceUpdaterService updater) {
        this.updater = updater;
    }

    @Scheduled(fixedRateString = "${prices.update.rate:60000}")
    public void scheduledUpdate() {
        updater.updateAllPrices();
    }
}
