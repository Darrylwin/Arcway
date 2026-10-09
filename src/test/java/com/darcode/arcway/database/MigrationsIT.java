package com.darcode.arcway.database;

import com.darcode.arcway.support.PostgresContainerConfig;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.test.context.ActiveProfiles;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
@ActiveProfiles("test")
@Import(PostgresContainerConfig.class)
class MigrationsIT {

    @Autowired
    private JdbcClient jdbc;

    @Test
    void requiredExtensionsAreInstalled() {
        List<String> installed = jdbc.sql("SELECT extname FROM pg_extension")
            .query(String.class)
            .list();

        assertThat(installed).contains("citext", "btree_gist", "pg_trgm");
    }
}
