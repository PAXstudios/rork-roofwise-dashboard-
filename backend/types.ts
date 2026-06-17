/* eslint-disable */
// AUTO-GENERATED — DO NOT EDIT
// Run migrations to regenerate.

export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      audit_log: {
        Row: {
          action: string
          actor_id: string | null
          created_at: string
          id: string
          metadata: Json | null
          target_id: string
          target_type: string
        }
        Insert: {
          action: string
          actor_id?: string | null
          created_at?: string
          id?: string
          metadata?: Json | null
          target_id: string
          target_type: string
        }
        Update: {
          action?: string
          actor_id?: string | null
          created_at?: string
          id?: string
          metadata?: Json | null
          target_id?: string
          target_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "audit_log_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      consensus_reviews: {
        Row: {
          created_at: string
          damage_feedback_id: string
          id: string
          inspection_photo_id: string
          reviewer_bounding_box: Json | null
          reviewer_confidence: string | null
          reviewer_damage_type: string
          reviewer_severity: number | null
          reviewer_user_id: string
        }
        Insert: {
          created_at?: string
          damage_feedback_id: string
          id?: string
          inspection_photo_id: string
          reviewer_bounding_box?: Json | null
          reviewer_confidence?: string | null
          reviewer_damage_type: string
          reviewer_severity?: number | null
          reviewer_user_id: string
        }
        Update: {
          created_at?: string
          damage_feedback_id?: string
          id?: string
          inspection_photo_id?: string
          reviewer_bounding_box?: Json | null
          reviewer_confidence?: string | null
          reviewer_damage_type?: string
          reviewer_severity?: number | null
          reviewer_user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "consensus_reviews_damage_feedback_id_fkey"
            columns: ["damage_feedback_id"]
            isOneToOne: false
            referencedRelation: "damage_feedback"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "consensus_reviews_inspection_photo_id_fkey"
            columns: ["inspection_photo_id"]
            isOneToOne: false
            referencedRelation: "inspection_photos"
            referencedColumns: ["id"]
          },
        ]
      }
      corrections: {
        Row: {
          admin_notes: string | null
          categories_affected: string[]
          corrected_at: string
          corrected_detection: Json
          correction_type: string
          created_at: string
          delta: Json
          id: string
          inspection_id: string
          original_detection: Json
          photo_hash: string | null
          photo_id: string
          photo_url: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          slope_id: string | null
          status: string
          user_id: string
        }
        Insert: {
          admin_notes?: string | null
          categories_affected?: string[]
          corrected_at: string
          corrected_detection: Json
          correction_type: string
          created_at?: string
          delta: Json
          id: string
          inspection_id: string
          original_detection: Json
          photo_hash?: string | null
          photo_id: string
          photo_url?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          slope_id?: string | null
          status?: string
          user_id: string
        }
        Update: {
          admin_notes?: string | null
          categories_affected?: string[]
          corrected_at?: string
          corrected_detection?: Json
          correction_type?: string
          created_at?: string
          delta?: Json
          id?: string
          inspection_id?: string
          original_detection?: Json
          photo_hash?: string | null
          photo_id?: string
          photo_url?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          slope_id?: string | null
          status?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "corrections_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "corrections_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      damage_feedback: {
        Row: {
          ai_bounding_box: Json | null
          ai_confidence: number | null
          ai_damage_type: string | null
          ai_model_version: string | null
          ai_prediction_id: string | null
          created_at: string
          id: string
          included_in_training: boolean | null
          inspection_photo_id: string
          training_batch_id: string | null
          user_action: string
          user_bounding_box: Json | null
          user_damage_type: string | null
          user_haag_certified: boolean | null
          user_id: string
          user_notes: string | null
          user_severity: number | null
          user_trust_score: number | null
          user_years_experience: number | null
          validation_status: string | null
        }
        Insert: {
          ai_bounding_box?: Json | null
          ai_confidence?: number | null
          ai_damage_type?: string | null
          ai_model_version?: string | null
          ai_prediction_id?: string | null
          created_at?: string
          id?: string
          included_in_training?: boolean | null
          inspection_photo_id: string
          training_batch_id?: string | null
          user_action: string
          user_bounding_box?: Json | null
          user_damage_type?: string | null
          user_haag_certified?: boolean | null
          user_id: string
          user_notes?: string | null
          user_severity?: number | null
          user_trust_score?: number | null
          user_years_experience?: number | null
          validation_status?: string | null
        }
        Update: {
          ai_bounding_box?: Json | null
          ai_confidence?: number | null
          ai_damage_type?: string | null
          ai_model_version?: string | null
          ai_prediction_id?: string | null
          created_at?: string
          id?: string
          included_in_training?: boolean | null
          inspection_photo_id?: string
          training_batch_id?: string | null
          user_action?: string
          user_bounding_box?: Json | null
          user_damage_type?: string | null
          user_haag_certified?: boolean | null
          user_id?: string
          user_notes?: string | null
          user_severity?: number | null
          user_trust_score?: number | null
          user_years_experience?: number | null
          validation_status?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "damage_feedback_inspection_photo_id_fkey"
            columns: ["inspection_photo_id"]
            isOneToOne: false
            referencedRelation: "inspection_photos"
            referencedColumns: ["id"]
          },
        ]
      }
      inspection_photos: {
        Row: {
          analyzed: boolean
          capture_mode: string | null
          captured_at: string
          customer_id: string
          damage_markers: Json | null
          elevation_feet: number | null
          findings: Json | null
          id: string
          pitch_degrees: number | null
          slope: string | null
          squares_covered: number | null
          storage_path: string
          updated_at: string
          user_id: string
        }
        Insert: {
          analyzed?: boolean
          capture_mode?: string | null
          captured_at?: string
          customer_id: string
          damage_markers?: Json | null
          elevation_feet?: number | null
          findings?: Json | null
          id?: string
          pitch_degrees?: number | null
          slope?: string | null
          squares_covered?: number | null
          storage_path: string
          updated_at?: string
          user_id: string
        }
        Update: {
          analyzed?: boolean
          capture_mode?: string | null
          captured_at?: string
          customer_id?: string
          damage_markers?: Json | null
          elevation_feet?: number | null
          findings?: Json | null
          id?: string
          pitch_degrees?: number | null
          slope?: string | null
          squares_covered?: number | null
          storage_path?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      leads: {
        Row: {
          address: string
          adjuster_name: string
          adjuster_phone: string
          claim_packet_summary: string
          date_of_loss: string | null
          email: string
          estimated_value: string
          id: string
          insurance_company: string
          owner_name: string
          phone: string
          policy_number: string
          stage: string
          storm_tagged: boolean
          updated_at: string
          user_id: string
        }
        Insert: {
          address?: string
          adjuster_name?: string
          adjuster_phone?: string
          claim_packet_summary?: string
          date_of_loss?: string | null
          email?: string
          estimated_value?: string
          id: string
          insurance_company?: string
          owner_name?: string
          phone?: string
          policy_number?: string
          stage?: string
          storm_tagged?: boolean
          updated_at?: string
          user_id?: string
        }
        Update: {
          address?: string
          adjuster_name?: string
          adjuster_phone?: string
          claim_packet_summary?: string
          date_of_loss?: string | null
          email?: string
          estimated_value?: string
          id?: string
          insurance_company?: string
          owner_name?: string
          phone?: string
          policy_number?: string
          stage?: string
          storm_tagged?: boolean
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      training_examples: {
        Row: {
          authority_weight: number
          correction_id: string
          dataset_version: string | null
          id: string
          labels: Json
          photo_url: string
          promoted_at: string
          promoted_by: string
        }
        Insert: {
          authority_weight: number
          correction_id: string
          dataset_version?: string | null
          id?: string
          labels: Json
          photo_url: string
          promoted_at?: string
          promoted_by: string
        }
        Update: {
          authority_weight?: number
          correction_id?: string
          dataset_version?: string | null
          id?: string
          labels?: Json
          photo_url?: string
          promoted_at?: string
          promoted_by?: string
        }
        Relationships: [
          {
            foreignKeyName: "training_examples_correction_id_fkey"
            columns: ["correction_id"]
            isOneToOne: true
            referencedRelation: "corrections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "training_examples_promoted_by_fkey"
            columns: ["promoted_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      user_trust_profile: {
        Row: {
          agreement_rate: number
          current_trust_score: number
          haag_certification_number: string | null
          haag_certified: boolean
          last_updated: string
          total_corrections: number
          user_id: string
          validated_corrections: number
          years_experience: number
        }
        Insert: {
          agreement_rate?: number
          current_trust_score?: number
          haag_certification_number?: string | null
          haag_certified?: boolean
          last_updated?: string
          total_corrections?: number
          user_id: string
          validated_corrections?: number
          years_experience?: number
        }
        Update: {
          agreement_rate?: number
          current_trust_score?: number
          haag_certification_number?: string | null
          haag_certified?: boolean
          last_updated?: string
          total_corrections?: number
          user_id?: string
          validated_corrections?: number
          years_experience?: number
        }
        Relationships: []
      }
      users: {
        Row: {
          authority_score: number
          corrections_approved: number
          corrections_rejected: number
          created_at: string
          device_id: string
          display_name: string | null
          email: string | null
          haag_certification_number: string | null
          haag_certified: boolean
          id: string
          total_corrections: number
          updated_at: string
        }
        Insert: {
          authority_score?: number
          corrections_approved?: number
          corrections_rejected?: number
          created_at?: string
          device_id: string
          display_name?: string | null
          email?: string | null
          haag_certification_number?: string | null
          haag_certified?: boolean
          id?: string
          total_corrections?: number
          updated_at?: string
        }
        Update: {
          authority_score?: number
          corrections_approved?: number
          corrections_rejected?: number
          created_at?: string
          device_id?: string
          display_name?: string | null
          email?: string | null
          haag_certification_number?: string | null
          haag_certified?: boolean
          id?: string
          total_corrections?: number
          updated_at?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      current_user_trust_score: { Args: never; Returns: number }
      is_admin: { Args: never; Returns: boolean }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
