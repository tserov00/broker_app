package com.example.broker_app.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.util.UriComponentsBuilder;

import java.util.Map;

@Service
public class FinnhubService {
    private final RestTemplate restTemplate = new RestTemplate();

    @Value("${finnhub.api.key}")
    private String apiKey;

    public Double getLastPrice(String ticker) {
        String url = UriComponentsBuilder
                .fromHttpUrl("https://finnhub.io/api/v1/quote")
                .queryParam("symbol", ticker)
                .queryParam("token", apiKey)
                .toUriString();

        Map<?, ?> resp = restTemplate.getForObject(url, Map.class);
        if (resp != null && resp.containsKey("c")) {
            Number c = (Number) resp.get("c");
            return c != null ? c.doubleValue() : null;
        }
        return null;
    }
}
