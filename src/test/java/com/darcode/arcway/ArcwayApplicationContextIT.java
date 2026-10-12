package com.darcode.arcway;

import static org.assertj.core.api.Assertions.assertThat;

import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import javax.sql.DataSource;

import com.darcode.arcway.testsupport.AbstractIntegrationTest;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

/**
 * Preuve de base : le contexte démarre et l'application se connecte avec un
 * rôle sans privilège. Tout le modèle d'isolation repose sur ce second point.
 */
class ArcwayApplicationContextIT extends AbstractIntegrationTest {

    @Autowired
    private DataSource dataSource;

    @Test
    void applicationConnectsAsUnprivilegedRole() throws SQLException {
        String sql = "SELECT current_user, rolsuper, rolbypassrls "
            + "FROM pg_roles WHERE rolname = current_user";

        try (Connection connection = dataSource.getConnection();
             Statement statement = connection.createStatement();
             ResultSet row = statement.executeQuery(sql)) {

            assertThat(row.next()).isTrue();
            assertThat(row.getString(1)).isEqualTo("arcway_app");
            assertThat(row.getBoolean(2)).as("rolsuper").isFalse();
            assertThat(row.getBoolean(3)).as("rolbypassrls").isFalse();
        }
    }
}
