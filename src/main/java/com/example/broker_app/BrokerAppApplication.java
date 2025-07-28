package com.example.broker_app;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@EnableScheduling
@SpringBootApplication
public class BrokerAppApplication {
    public static void main(String[] args) {
        SpringApplication.run(BrokerAppApplication.class, args);
    }
}
