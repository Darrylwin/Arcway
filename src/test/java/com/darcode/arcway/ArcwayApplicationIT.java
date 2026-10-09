package com.darcode.arcway;

import com.darcode.arcway.support.PostgresContainerConfig;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;

@SpringBootTest
@Import(PostgresContainerConfig.class)
class ArcwayApplicationIT {

    @Test
    void contextLoads() {
    }

}
