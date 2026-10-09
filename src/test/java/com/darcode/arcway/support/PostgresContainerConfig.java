package com.darcode.arcway.support;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.test.context.DynamicPropertyRegistrar;
import org.testcontainers.postgresql.PostgreSQLContainer;
import org.testcontainers.utility.MountableFile;

@TestConfiguration(proxyBeanMethods = false)
public class PostgresContainerConfig {

    public static final String MIGRATOR_USER = "arcway_migrator";
    public static final String MIGRATOR_PASSWORD = "migrator-test-password";
    public static final String APP_USER = "arcway_app";
    public static final String APP_PASSWORD = "app-test-password";

    private static final String ROLES_SCRIPT = "ops/db/init/01-roles.sh";

    @Bean
    PostgreSQLContainer postgres() {
        return new PostgreSQLContainer("postgres:17")
            .withEnv("DB_MIGRATOR_USER", MIGRATOR_USER)
            .withEnv("DB_MIGRATOR_PASSWORD", MIGRATOR_PASSWORD)
            .withEnv("DB_APP_USER", APP_USER)
            .withEnv("DB_APP_PASSWORD", APP_PASSWORD)
            .withCopyFileToContainer(
                MountableFile.forHostPath(ROLES_SCRIPT, 0755),
                "/docker-entrypoint-initdb.d/01-roles.sh");
    }

    @Bean
    DynamicPropertyRegistrar databaseProperties(PostgreSQLContainer postgres) {
        return registry -> {
            registry.add("spring.datasource.url", postgres::getJdbcUrl);
            registry.add("spring.datasource.username", () -> APP_USER);
            registry.add("spring.datasource.password", () -> APP_PASSWORD);
            registry.add("spring.flyway.url", postgres::getJdbcUrl);
            registry.add("spring.flyway.user", () -> MIGRATOR_USER);
            registry.add("spring.flyway.password", () -> MIGRATOR_PASSWORD);
        };
    }
}
