package com.darcode.arcway.database;

import com.darcode.arcway.support.PostgresContainerConfig;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.support.TransactionTemplate;

import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
@ActiveProfiles("test")
@Import(PostgresContainerConfig.class)
class MigrationsIT {

    @Autowired
    private JdbcClient jdbc;

    @Autowired
    private TransactionTemplate tx;

    @Test
    void requiredExtensionsAreInstalled() {
        List<String> installed = jdbc.sql("SELECT extname FROM pg_extension")
            .query(String.class)
            .list();

        assertThat(installed).contains("citext", "btree_gist", "pg_trgm");
    }

    @Test
    void allEnumTypesAreCreated() {
        Integer count = jdbc.sql("""
            SELECT count(*) FROM pg_type
            WHERE typtype = 'e' AND typnamespace = 'public'::regnamespace
            """).query(Integer.class).single();

        assertThat(count).isEqualTo(20);
    }

    @Test
    void enumValuesKeepTheirDeclaredOrder() {
        List<String> labels = jdbc.sql("""
            SELECT enumlabel FROM pg_enum
            WHERE enumtypid = 'participation_status'::regtype
            ORDER BY enumsortorder
            """).query(String.class).list();

        assertThat(labels).containsExactly(
            "PENDING", "PLAYED", "DNP_COACH", "DNP_INJURED", "DNP_ABSENT", "DNP_SUSPENDED");
    }

    @Test
    void sessionHelpersReturnNullWithoutContext() {
        Boolean allNull = tx.execute(status -> jdbc.sql("""
            SELECT app_org_id() IS NULL AND app_user_id() IS NULL
            """).query(Boolean.class).single());

        assertThat(allNull).isTrue();
    }

    @Test
    void sessionHelpersReadTransactionLocalSettings() {
        UUID org = UUID.randomUUID();

        String read = tx.execute(status -> {
            jdbc.sql("SELECT set_config('app.org_id', :v, true)")
                .param("v", org.toString()).query().singleRow();
            return jdbc.sql("SELECT app_org_id()::text").query(String.class).single();
        });

        assertThat(read).isEqualTo(org.toString());
    }

    @Test
    void emptyStringSettingIsTreatedAsNull() {
        Boolean isNull = tx.execute(status -> {
            jdbc.sql("SELECT set_config('app.org_id', '', true)").query().singleRow();
            return jdbc.sql("SELECT app_org_id() IS NULL").query(Boolean.class).single();
        });

        assertThat(isNull).isTrue();
    }
}
