package com.darcode.arcway.database;

import com.darcode.arcway.support.PostgresContainerConfig;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.test.context.ActiveProfiles;

import java.sql.SQLException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest
@ActiveProfiles("test")
@Import(PostgresContainerConfig.class)
class DatabaseRolesIT {

    @Autowired
    private JdbcClient jdbc;

    @Test
    void applicationConnectsWithTheRestrictedRole() {
        String user = jdbc.sql("SELECT current_user").query(String.class).single();

        assertThat(user).isEqualTo(PostgresContainerConfig.APP_USER);
    }

    @Test
    void applicationRoleIsNeitherSuperuserNorBypassRls() {
        Boolean restricted = jdbc.sql("""
            SELECT NOT rolsuper AND NOT rolbypassrls
            FROM pg_roles WHERE rolname = current_user
            """).query(Boolean.class).single();

        assertThat(restricted).isTrue();
    }

    @Test
    void applicationRoleCannotCreateObjects() {
        // 42501 = insufficient_privilege : indépendant de la langue du serveur.
        assertThatThrownBy(() -> jdbc.sql("CREATE TABLE should_fail (id int)").update())
            .rootCause()
            .isInstanceOfSatisfying(SQLException.class,
                e -> assertThat(e.getSQLState()).isEqualTo("42501"));
    }

    @Test
    void migratorRoleBypassesRowLevelSecurity() {
        Boolean bypass = jdbc.sql("SELECT rolbypassrls FROM pg_roles WHERE rolname = :name")
            .param("name", PostgresContainerConfig.MIGRATOR_USER)
            .query(Boolean.class).single();

        assertThat(bypass).isTrue();
    }

    @Test
    void migrationsAreOwnedByTheMigratorRole() {
        String owner = jdbc.sql("""
            SELECT pg_get_userbyid(typowner) FROM pg_type WHERE typname = 'org_role'
            """).query(String.class).single();

        assertThat(owner).isEqualTo(PostgresContainerConfig.MIGRATOR_USER);
    }
}
