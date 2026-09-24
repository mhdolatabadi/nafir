package ir.mhdolatabadi.sot.health;

import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1")
class HealthController {

  @GetMapping("/health")
  Map<String, String> health() {
    return Map.of("status", "ok");
  }
}
