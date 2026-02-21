// Package mysql implements MySQL database adapter for Cats Company.
package mysql

import (
	"database/sql"
	"time"

	_ "github.com/go-sql-driver/mysql"
)

// Adapter is the MySQL database adapter.
type Adapter struct {
	db     *sql.DB
	dsn    string
	prefix string
}

// Config holds MySQL connection configuration.
type Config struct {
	DSN    string `json:"dsn"`
	Prefix string `json:"prefix"`
}

// Open initializes the database connection.
func (a *Adapter) Open(dsn string) error {
	var err error
	a.dsn = dsn
	a.db, err = sql.Open("mysql", dsn)
	if err != nil {
		return err
	}
	a.db.SetMaxOpenConns(64)
	a.db.SetMaxIdleConns(16)
	a.db.SetConnMaxLifetime(10 * time.Minute)
	return a.db.Ping()
}

// Close shuts down the database connection.
func (a *Adapter) Close() error {
	if a.db != nil {
		return a.db.Close()
	}
	return nil
}

// DB returns the underlying sql.DB for direct access.
func (a *Adapter) DB() *sql.DB {
	return a.db
}

// IsConnected checks if the database connection is still alive.
func (a *Adapter) IsConnected() bool {
	if a.db == nil {
		return false
	}
	return a.db.Ping() == nil
}
