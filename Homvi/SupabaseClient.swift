//
//  SupabaseClient.swift
//  Homvi
//
//  Created by Issam Merhej on 4/25/26.
//

internal import Foundation
internal import Supabase

let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://tyfdsrxkswwwfmdkjknk.supabase.co")!,
    supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InR5ZmRzcnhrc3d3d2ZtZGtqa25rIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcxNDU2OTMsImV4cCI6MjA5MjcyMTY5M30.ibEIdJAqvy-ftLB3PP0WTqLUqmRPC3p6FvbTx_8rONE",
    options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
            emitLocalSessionAsInitialSession: true
        )
    )
)
