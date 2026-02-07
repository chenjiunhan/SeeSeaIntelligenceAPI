package main

import (
	"database/sql"
	"log"
	"os"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
	_ "github.com/lib/pq"
)

var db *sql.DB

func main() {
	// Load .env file
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found")
	}

	// Initialize database connection
	var err error
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL not set")
	}

	// Add sslmode=disable if not present
	if dbURL != "" && !strings.Contains(dbURL, "sslmode") {
		if strings.Contains(dbURL, "?") {
			dbURL += "&sslmode=disable"
		} else {
			dbURL += "?sslmode=disable"
		}
	}

	db, err = sql.Open("postgres", dbURL)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer db.Close()

	// Test database connection
	if err := db.Ping(); err != nil {
		log.Fatalf("Failed to ping database: %v", err)
	}
	log.Println("✅ Database connected successfully")

	// Set Gin mode
	gin.SetMode(gin.ReleaseMode)

	// Initialize router
	router := gin.Default()

	// CORS middleware
	router.Use(corsMiddleware())

	// Health check
	router.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"status": "OK",
			"service": "seesea-api-go",
		})
	})

	// API routes
	v1 := router.Group("/api/v1")
	{
		// Vessels routes
		vessels := v1.Group("/vessels")
		{
			vessels.GET("/:chokepoint", getVessels)
			vessels.GET("/:chokepoint/summary", getVesselSummary)
		}

		// WebSocket
		router.GET("/ws", handleWebSocket)
	}

	// Start server
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("🚀 Go API server starting on port %s", port)
	if err := router.Run(":" + port); err != nil {
		log.Fatal(err)
	}
}

// CORS middleware
func corsMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}

		c.Next()
	}
}

// Data structures
type VesselArrival struct {
	Date          string `json:"date"`
	Chokepoint    string `json:"chokepoint"`
	VesselCount   int    `json:"vessel_count"`
	Container     int    `json:"container"`
	DryBulk       int    `json:"dry_bulk"`
	GeneralCargo  int    `json:"general_cargo"`
	Roro          int    `json:"roro"`
	Tanker        int    `json:"tanker"`
	CollectedAt   string `json:"collected_at"`
}

type VesselsResponse struct {
	Chokepoint string          `json:"chokepoint"`
	Data       []VesselArrival `json:"data"`
	Total      int             `json:"total"`
	StartDate  string          `json:"start_date,omitempty"`
	EndDate    string          `json:"end_date,omitempty"`
}

// Handler: Get vessels by chokepoint
func getVessels(c *gin.Context) {
	chokepoint := c.Param("chokepoint")

	// Optional query parameters
	limit := c.DefaultQuery("limit", "30")
	startDate := c.Query("start_date")
	endDate := c.Query("end_date")

	// Build SQL query
	query := `
		SELECT date, chokepoint, vessel_count, container, dry_bulk,
		       general_cargo, roro, tanker, collected_at
		FROM vessel_arrivals
		WHERE chokepoint = $1
	`
	args := []interface{}{chokepoint}
	argIndex := 2

	// Add date filters if provided
	if startDate != "" {
		query += " AND date >= $2"
		args = append(args, startDate)
		argIndex++
	}
	if endDate != "" {
		if startDate != "" {
			query += " AND date <= $3"
		} else {
			query += " AND date <= $2"
		}
		args = append(args, endDate)
		argIndex++
	}

	query += " ORDER BY date DESC LIMIT $" + string(rune('0'+argIndex))
	args = append(args, limit)

	// Execute query
	rows, err := db.Query(query, args...)
	if err != nil {
		c.JSON(500, gin.H{"error": "Database query failed", "details": err.Error()})
		return
	}
	defer rows.Close()

	// Parse results
	var vessels []VesselArrival
	for rows.Next() {
		var v VesselArrival
		var collectedAt time.Time
		var date time.Time

		err := rows.Scan(
			&date, &v.Chokepoint, &v.VesselCount, &v.Container,
			&v.DryBulk, &v.GeneralCargo, &v.Roro, &v.Tanker, &collectedAt,
		)
		if err != nil {
			c.JSON(500, gin.H{"error": "Failed to parse data", "details": err.Error()})
			return
		}

		v.Date = date.Format("2006-01-02")
		v.CollectedAt = collectedAt.Format(time.RFC3339)
		vessels = append(vessels, v)
	}

	// Check for errors during iteration
	if err := rows.Err(); err != nil {
		c.JSON(500, gin.H{"error": "Error reading results", "details": err.Error()})
		return
	}

	// Return empty array if no data found
	if vessels == nil {
		vessels = []VesselArrival{}
	}

	// Build response
	response := VesselsResponse{
		Chokepoint: chokepoint,
		Data:       vessels,
		Total:      len(vessels),
		StartDate:  startDate,
		EndDate:    endDate,
	}

	c.JSON(200, response)
}

type VesselSummary struct {
	Chokepoint        string  `json:"chokepoint"`
	TotalVessels      int     `json:"total_vessels"`
	AvgDailyVessels   float64 `json:"avg_daily_vessels"`
	TotalContainer    int     `json:"total_container"`
	TotalDryBulk      int     `json:"total_dry_bulk"`
	TotalGeneralCargo int     `json:"total_general_cargo"`
	TotalRoro         int     `json:"total_roro"`
	TotalTanker       int     `json:"total_tanker"`
	DaysWithData      int     `json:"days_with_data"`
	LatestDate        string  `json:"latest_date"`
}

// Handler: Get vessel summary by chokepoint
func getVesselSummary(c *gin.Context) {
	chokepoint := c.Param("chokepoint")

	// Optional date range
	startDate := c.Query("start_date")
	endDate := c.Query("end_date")

	// Build SQL query
	query := `
		SELECT
			COUNT(*) as days_with_data,
			SUM(vessel_count) as total_vessels,
			AVG(vessel_count) as avg_daily_vessels,
			SUM(container) as total_container,
			SUM(dry_bulk) as total_dry_bulk,
			SUM(general_cargo) as total_general_cargo,
			SUM(roro) as total_roro,
			SUM(tanker) as total_tanker,
			MAX(date) as latest_date
		FROM vessel_arrivals
		WHERE chokepoint = $1
	`
	args := []interface{}{chokepoint}

	// Add date filters if provided
	if startDate != "" {
		query += " AND date >= $2"
		args = append(args, startDate)
	}
	if endDate != "" {
		if startDate != "" {
			query += " AND date <= $3"
		} else {
			query += " AND date <= $2"
		}
		args = append(args, endDate)
	}

	// Execute query
	var summary VesselSummary
	var latestDate time.Time

	err := db.QueryRow(query, args...).Scan(
		&summary.DaysWithData,
		&summary.TotalVessels,
		&summary.AvgDailyVessels,
		&summary.TotalContainer,
		&summary.TotalDryBulk,
		&summary.TotalGeneralCargo,
		&summary.TotalRoro,
		&summary.TotalTanker,
		&latestDate,
	)

	if err != nil {
		if err == sql.ErrNoRows {
			c.JSON(404, gin.H{"error": "No data found for this chokepoint"})
		} else {
			c.JSON(500, gin.H{"error": "Database query failed", "details": err.Error()})
		}
		return
	}

	summary.Chokepoint = chokepoint
	summary.LatestDate = latestDate.Format("2006-01-02")

	c.JSON(200, summary)
}

func handleWebSocket(c *gin.Context) {
	c.JSON(200, gin.H{
		"message": "WebSocket will be implemented",
	})
}
