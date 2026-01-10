package main

import (
	"crypto/ecdsa"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"

	"github.com/ethereum/go-ethereum/crypto"
	"golang.org/x/crypto/openpgp/armor"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: genkey <keyfile> [description]")
		fmt.Println("  Generates a guardian key in Wormhole's armored format")
		os.Exit(1)
	}

	keyPath := os.Args[1]
	desc := ""
	if len(os.Args) >= 3 {
		desc = os.Args[2]
	}

	// Check if file exists
	if _, err := os.Stat(keyPath); err == nil {
		fmt.Printf("Error: Key file already exists: %s\n", keyPath)
		os.Exit(1)
	}

	// Generate ECDSA key
	key, err := ecdsa.GenerateKey(crypto.S256(), rand.Reader)
	if err != nil {
		fmt.Printf("Error generating key: %v\n", err)
		os.Exit(1)
	}

	// Get the private key bytes
	keyBytes := crypto.FromECDSA(key)

	// Create directory if needed
	dir := filepath.Dir(keyPath)
	if dir != "" && dir != "." {
		if err := os.MkdirAll(dir, 0700); err != nil {
			fmt.Printf("Error creating directory: %v\n", err)
			os.Exit(1)
		}
	}

	// Write armored key file
	f, err := os.OpenFile(keyPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		fmt.Printf("Error creating file: %v\n", err)
		os.Exit(1)
	}
	defer f.Close()

	// Build headers
	headers := map[string]string{
		"PublicKey": crypto.PubkeyToAddress(key.PublicKey).String(),
	}
	if desc != "" {
		headers["Description"] = desc
	}

	// Create armor encoder
	w, err := armor.Encode(f, "WORMHOLE GUARDIAN PRIVATE KEY", headers)
	if err != nil {
		fmt.Printf("Error creating armor encoder: %v\n", err)
		os.Exit(1)
	}

	// Write protobuf-encoded key data
	// Protobuf encoding for GuardianKey message:
	// Field 1 (Data): tag = 0x0a (field 1, wire type 2 = length-delimited)
	// Field 2 (UnsafeDeterministicKey): not set (defaults to false)
	protoData := make([]byte, 0, 2+len(keyBytes))
	protoData = append(protoData, 0x0a)             // field 1, wire type 2
	protoData = append(protoData, byte(len(keyBytes))) // length
	protoData = append(protoData, keyBytes...)     // data

	if _, err := w.Write(protoData); err != nil {
		fmt.Printf("Error writing key: %v\n", err)
		os.Exit(1)
	}

	if err := w.Close(); err != nil {
		fmt.Printf("Error closing armor: %v\n", err)
		os.Exit(1)
	}

	// Print results
	fmt.Printf("Generated key: %s\n", keyPath)
	fmt.Printf("Address: %s\n", crypto.PubkeyToAddress(key.PublicKey).String())
	fmt.Printf("Private Key (hex): %s\n", hex.EncodeToString(keyBytes))
}
