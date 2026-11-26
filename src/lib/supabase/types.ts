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
    PostgrestVersion: "14.18"
  }
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      ai_usage: {
        Row: {
          acting_profile_id: string | null
          cost_usd: number
          created_at: string
          id: string
          request_count: number
          updated_at: string
          usage_day: string
          user_id: string
        }
        Insert: {
          acting_profile_id?: string | null
          cost_usd?: number
          created_at?: string
          id?: string
          request_count?: number
          updated_at?: string
          usage_day: string
          user_id: string
        }
        Update: {
          acting_profile_id?: string | null
          cost_usd?: number
          created_at?: string
          id?: string
          request_count?: number
          updated_at?: string
          usage_day?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_usage_acting_profile_id_fkey"
            columns: ["acting_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      app_settings: {
        Row: {
          ai_daily_call_limit: number
          created_at: string
          id: string
          max_cost_per_call_usd: number
          monthly_spend_cap_usd: number
          singleton: boolean
          updated_at: string
        }
        Insert: {
          ai_daily_call_limit?: number
          created_at?: string
          id?: string
          max_cost_per_call_usd?: number
          monthly_spend_cap_usd?: number
          singleton?: boolean
          updated_at?: string
        }
        Update: {
          ai_daily_call_limit?: number
          created_at?: string
          id?: string
          max_cost_per_call_usd?: number
          monthly_spend_cap_usd?: number
          singleton?: boolean
          updated_at?: string
        }
        Relationships: []
      }
      business_details: {
        Row: {
          address: string | null
          category: string | null
          created_at: string
          id: string
          opening_hours: Json
          phone: string | null
          profile_id: string
          updated_at: string
          website: string | null
        }
        Insert: {
          address?: string | null
          category?: string | null
          created_at?: string
          id?: string
          opening_hours?: Json
          phone?: string | null
          profile_id: string
          updated_at?: string
          website?: string | null
        }
        Update: {
          address?: string | null
          category?: string | null
          created_at?: string
          id?: string
          opening_hours?: Json
          phone?: string | null
          profile_id?: string
          updated_at?: string
          website?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "business_details_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      circle_members: {
        Row: {
          circle_id: string
          created_at: string
          id: string
          member_profile_id: string
        }
        Insert: {
          circle_id: string
          created_at?: string
          id?: string
          member_profile_id: string
        }
        Update: {
          circle_id?: string
          created_at?: string
          id?: string
          member_profile_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "circle_members_circle_id_fkey"
            columns: ["circle_id"]
            isOneToOne: false
            referencedRelation: "circles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "circle_members_member_profile_id_fkey"
            columns: ["member_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      circles: {
        Row: {
          created_at: string
          id: string
          is_all_followers: boolean
          member_label: string | null
          owner_profile_id: string
          private_name: string
          show_member_label: boolean
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          is_all_followers?: boolean
          member_label?: string | null
          owner_profile_id: string
          private_name: string
          show_member_label?: boolean
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          is_all_followers?: boolean
          member_label?: string | null
          owner_profile_id?: string
          private_name?: string
          show_member_label?: boolean
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "circles_owner_profile_id_fkey"
            columns: ["owner_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      content_items: {
        Row: {
          audience: Database["public"]["Enums"]["audience"]
          content_type: Database["public"]["Enums"]["content_type"]
          created_at: string
          details: Json
          expires_at: string | null
          group_id: string | null
          id: string
          owner_profile_id: string
          parent_id: string | null
          updated_at: string
        }
        Insert: {
          audience: Database["public"]["Enums"]["audience"]
          content_type: Database["public"]["Enums"]["content_type"]
          created_at?: string
          details?: Json
          expires_at?: string | null
          group_id?: string | null
          id?: string
          owner_profile_id: string
          parent_id?: string | null
          updated_at?: string
        }
        Update: {
          audience?: Database["public"]["Enums"]["audience"]
          content_type?: Database["public"]["Enums"]["content_type"]
          created_at?: string
          details?: Json
          expires_at?: string | null
          group_id?: string | null
          id?: string
          owner_profile_id?: string
          parent_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "content_items_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "content_items_owner_profile_id_fkey"
            columns: ["owner_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "content_items_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "content_items"
            referencedColumns: ["id"]
          },
        ]
      }
      conversation_members: {
        Row: {
          conversation_id: string
          created_at: string
          id: string
          profile_id: string
        }
        Insert: {
          conversation_id: string
          created_at?: string
          id?: string
          profile_id: string
        }
        Update: {
          conversation_id?: string
          created_at?: string
          id?: string
          profile_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "conversation_members_conversation_id_fkey"
            columns: ["conversation_id"]
            isOneToOne: false
            referencedRelation: "conversations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "conversation_members_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      conversations: {
        Row: {
          created_at: string
          id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          updated_at?: string
        }
        Relationships: []
      }
      group_members: {
        Row: {
          created_at: string
          group_id: string
          id: string
          profile_id: string
        }
        Insert: {
          created_at?: string
          group_id: string
          id?: string
          profile_id: string
        }
        Update: {
          created_at?: string
          group_id?: string
          id?: string
          profile_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "group_members_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "group_members_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      groups: {
        Row: {
          circle_id: string | null
          created_at: string
          id: string
          name: string
          owner_profile_id: string
          updated_at: string
        }
        Insert: {
          circle_id?: string | null
          created_at?: string
          id?: string
          name: string
          owner_profile_id: string
          updated_at?: string
        }
        Update: {
          circle_id?: string | null
          created_at?: string
          id?: string
          name?: string
          owner_profile_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "groups_circle_id_fkey"
            columns: ["circle_id"]
            isOneToOne: false
            referencedRelation: "circles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "groups_owner_profile_id_fkey"
            columns: ["owner_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      item_circles: {
        Row: {
          circle_id: string
          content_item_id: string | null
          created_at: string
          id: string
          vouch_id: string | null
        }
        Insert: {
          circle_id: string
          content_item_id?: string | null
          created_at?: string
          id?: string
          vouch_id?: string | null
        }
        Update: {
          circle_id?: string
          content_item_id?: string | null
          created_at?: string
          id?: string
          vouch_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "item_circles_circle_id_fkey"
            columns: ["circle_id"]
            isOneToOne: false
            referencedRelation: "circles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "item_circles_content_item_id_fkey"
            columns: ["content_item_id"]
            isOneToOne: false
            referencedRelation: "content_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "item_circles_vouch_id_fkey"
            columns: ["vouch_id"]
            isOneToOne: false
            referencedRelation: "vouches"
            referencedColumns: ["id"]
          },
        ]
      }
      languages: {
        Row: {
          code: string
          created_at: string
          id: string
          name: string
        }
        Insert: {
          code: string
          created_at?: string
          id?: string
          name: string
        }
        Update: {
          code?: string
          created_at?: string
          id?: string
          name?: string
        }
        Relationships: []
      }
      lastfm_links: {
        Row: {
          created_at: string
          id: string
          profile_id: string
          updated_at: string
          username: string
        }
        Insert: {
          created_at?: string
          id?: string
          profile_id: string
          updated_at?: string
          username: string
        }
        Update: {
          created_at?: string
          id?: string
          profile_id?: string
          updated_at?: string
          username?: string
        }
        Relationships: [
          {
            foreignKeyName: "lastfm_links_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      message_translations: {
        Row: {
          body: string
          created_at: string
          id: string
          language_code: string
          message_id: string
        }
        Insert: {
          body: string
          created_at?: string
          id?: string
          language_code: string
          message_id: string
        }
        Update: {
          body?: string
          created_at?: string
          id?: string
          language_code?: string
          message_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "message_translations_language_code_fkey"
            columns: ["language_code"]
            isOneToOne: false
            referencedRelation: "languages"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "message_translations_message_id_fkey"
            columns: ["message_id"]
            isOneToOne: false
            referencedRelation: "messages"
            referencedColumns: ["id"]
          },
        ]
      }
      messages: {
        Row: {
          body: string
          conversation_id: string
          created_at: string
          id: string
          language_code: string
          sender_profile_id: string | null
          updated_at: string
        }
        Insert: {
          body: string
          conversation_id: string
          created_at?: string
          id?: string
          language_code: string
          sender_profile_id?: string | null
          updated_at?: string
        }
        Update: {
          body?: string
          conversation_id?: string
          created_at?: string
          id?: string
          language_code?: string
          sender_profile_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "messages_conversation_id_fkey"
            columns: ["conversation_id"]
            isOneToOne: false
            referencedRelation: "conversations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "messages_language_code_fkey"
            columns: ["language_code"]
            isOneToOne: false
            referencedRelation: "languages"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "messages_sender_profile_id_fkey"
            columns: ["sender_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      notifications: {
        Row: {
          actor_profile_id: string | null
          created_at: string
          data: Json
          id: string
          read_at: string | null
          recipient_profile_id: string
          reference_id: string | null
          type: Database["public"]["Enums"]["notification_type"]
        }
        Insert: {
          actor_profile_id?: string | null
          created_at?: string
          data?: Json
          id?: string
          read_at?: string | null
          recipient_profile_id: string
          reference_id?: string | null
          type: Database["public"]["Enums"]["notification_type"]
        }
        Update: {
          actor_profile_id?: string | null
          created_at?: string
          data?: Json
          id?: string
          read_at?: string | null
          recipient_profile_id?: string
          reference_id?: string | null
          type?: Database["public"]["Enums"]["notification_type"]
        }
        Relationships: [
          {
            foreignKeyName: "notifications_actor_profile_id_fkey"
            columns: ["actor_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_recipient_profile_id_fkey"
            columns: ["recipient_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profile_managers: {
        Row: {
          created_at: string
          id: string
          profile_id: string
          role: Database["public"]["Enums"]["manager_role"]
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          profile_id: string
          role: Database["public"]["Enums"]["manager_role"]
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          profile_id?: string
          role?: Database["public"]["Enums"]["manager_role"]
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "profile_managers_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profile_views: {
        Row: {
          created_at: string
          id: string
          viewed_at: string
          viewed_on: string
          viewed_profile_id: string
          viewer_profile_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          viewed_at?: string
          viewed_on: string
          viewed_profile_id: string
          viewer_profile_id: string
        }
        Update: {
          created_at?: string
          id?: string
          viewed_at?: string
          viewed_on?: string
          viewed_profile_id?: string
          viewer_profile_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "profile_views_viewed_profile_id_fkey"
            columns: ["viewed_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profile_views_viewer_profile_id_fkey"
            columns: ["viewer_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          avatar_path: string | null
          bio: string | null
          city: string | null
          country: string | null
          cover_path: string | null
          created_at: string
          display_name: string
          dot_colour: Database["public"]["Enums"]["dot_colour"]
          handle: string
          id: string
          mode_2006: boolean
          owner_user_id: string | null
          preferred_language: string
          search_tsv: unknown
          tags_text: string | null
          theme: Json
          type: Database["public"]["Enums"]["profile_type"]
          updated_at: string
          what_i_do: string[]
        }
        Insert: {
          avatar_path?: string | null
          bio?: string | null
          city?: string | null
          country?: string | null
          cover_path?: string | null
          created_at?: string
          display_name: string
          dot_colour?: Database["public"]["Enums"]["dot_colour"]
          handle: string
          id?: string
          mode_2006?: boolean
          owner_user_id?: string | null
          preferred_language?: string
          search_tsv?: unknown
          tags_text?: string | null
          theme?: Json
          type: Database["public"]["Enums"]["profile_type"]
          updated_at?: string
          what_i_do?: string[]
        }
        Update: {
          avatar_path?: string | null
          bio?: string | null
          city?: string | null
          country?: string | null
          cover_path?: string | null
          created_at?: string
          display_name?: string
          dot_colour?: Database["public"]["Enums"]["dot_colour"]
          handle?: string
          id?: string
          mode_2006?: boolean
          owner_user_id?: string | null
          preferred_language?: string
          search_tsv?: unknown
          tags_text?: string | null
          theme?: Json
          type?: Database["public"]["Enums"]["profile_type"]
          updated_at?: string
          what_i_do?: string[]
        }
        Relationships: [
          {
            foreignKeyName: "profiles_preferred_language_fkey"
            columns: ["preferred_language"]
            isOneToOne: false
            referencedRelation: "languages"
            referencedColumns: ["code"]
          },
        ]
      }
      relationships: {
        Row: {
          created_at: string
          id: string
          requester_profile_id: string
          status: Database["public"]["Enums"]["relationship_status"]
          target_profile_id: string
          type: Database["public"]["Enums"]["relationship_type"]
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          requester_profile_id: string
          status?: Database["public"]["Enums"]["relationship_status"]
          target_profile_id: string
          type: Database["public"]["Enums"]["relationship_type"]
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          requester_profile_id?: string
          status?: Database["public"]["Enums"]["relationship_status"]
          target_profile_id?: string
          type?: Database["public"]["Enums"]["relationship_type"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "relationships_requester_profile_id_fkey"
            columns: ["requester_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "relationships_target_profile_id_fkey"
            columns: ["target_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      reserved_handles: {
        Row: {
          created_at: string
          id: string
          word: string
        }
        Insert: {
          created_at?: string
          id?: string
          word: string
        }
        Update: {
          created_at?: string
          id?: string
          word?: string
        }
        Relationships: []
      }
      search_appearance_marks: {
        Row: {
          appeared_on: string
          created_at: string
          id: string
          profile_id: string
          searcher_profile_id: string
        }
        Insert: {
          appeared_on: string
          created_at?: string
          id?: string
          profile_id: string
          searcher_profile_id: string
        }
        Update: {
          appeared_on?: string
          created_at?: string
          id?: string
          profile_id?: string
          searcher_profile_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "search_appearance_marks_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "search_appearance_marks_searcher_profile_id_fkey"
            columns: ["searcher_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      search_appearances: {
        Row: {
          appeared_on: string
          count: number
          created_at: string
          id: string
          profile_id: string
          updated_at: string
        }
        Insert: {
          appeared_on: string
          count?: number
          created_at?: string
          id?: string
          profile_id: string
          updated_at?: string
        }
        Update: {
          appeared_on?: string
          count?: number
          created_at?: string
          id?: string
          profile_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "search_appearances_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      story_views: {
        Row: {
          created_at: string
          id: string
          story_id: string
          viewed_at: string
          viewer_profile_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          story_id: string
          viewed_at?: string
          viewer_profile_id: string
        }
        Update: {
          created_at?: string
          id?: string
          story_id?: string
          viewed_at?: string
          viewer_profile_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "story_views_story_id_fkey"
            columns: ["story_id"]
            isOneToOne: false
            referencedRelation: "content_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "story_views_viewer_profile_id_fkey"
            columns: ["viewer_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      vouches: {
        Row: {
          audience: Database["public"]["Enums"]["audience"]
          author_profile_id: string
          body: string
          created_at: string
          hidden_by_subject: boolean
          id: string
          subject_profile_id: string
          top8_position: number | null
          updated_at: string
        }
        Insert: {
          audience?: Database["public"]["Enums"]["audience"]
          author_profile_id: string
          body: string
          created_at?: string
          hidden_by_subject?: boolean
          id?: string
          subject_profile_id: string
          top8_position?: number | null
          updated_at?: string
        }
        Update: {
          audience?: Database["public"]["Enums"]["audience"]
          author_profile_id?: string
          body?: string
          created_at?: string
          hidden_by_subject?: boolean
          id?: string
          subject_profile_id?: string
          top8_position?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "vouches_author_profile_id_fkey"
            columns: ["author_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vouches_subject_profile_id_fkey"
            columns: ["subject_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      acts_as: { Args: { p_profile_id: string }; Returns: boolean }
      add_profile_manager: {
        Args: {
          p_business: string
          p_person_profile: string
          p_role: Database["public"]["Enums"]["manager_role"]
        }
        Returns: undefined
      }
      ai_can_call: { Args: never; Returns: boolean }
      ai_record_call: {
        Args: {
          p_acting_profile: string
          p_cost_usd: number
          p_user_id: string
        }
        Returns: undefined
      }
      can_view: {
        Args: { p_item_id: string; p_viewer_profile_id: string }
        Returns: boolean
      }
      create_content_item: {
        Args: {
          p_audience?: Database["public"]["Enums"]["audience"]
          p_circle_ids?: string[]
          p_details: Json
          p_group_id?: string
          p_owner: string
          p_parent_id?: string
          p_type: Database["public"]["Enums"]["content_type"]
        }
        Returns: string
      }
      create_vouch: {
        Args: {
          p_audience?: Database["public"]["Enums"]["audience"]
          p_author: string
          p_body: string
          p_circle_ids?: string[]
          p_subject: string
        }
        Returns: string
      }
      group_linked_circle: { Args: { p_group: string }; Returns: string }
      in_conversation: { Args: { p_conversation: string }; Returns: boolean }
      in_group: { Args: { p_group: string }; Returns: boolean }
      is_profile_owner: { Args: { p_profile_id: string }; Returns: boolean }
      item_audience: {
        Args: { p_item_id: string }
        Returns: {
          audience: Database["public"]["Enums"]["audience"]
          circle_ids: string[]
        }[]
      }
      my_profile_ids: { Args: never; Returns: string[] }
      my_profiles: {
        Args: never
        Returns: {
          display_name: string
          handle: string
          mode_2006: boolean
          preferred_language: string
          profile_id: string
          role: string
          type: Database["public"]["Enums"]["profile_type"]
        }[]
      }
      my_received_vouches: {
        Args: { p_subject: string }
        Returns: {
          author_profile_id: string
          body: string
          created_at: string
          hidden_by_subject: boolean
          vouch_id: string
        }[]
      }
      my_relationships: {
        Args: { p_acting: string }
        Returns: {
          created_at: string
          direction: string
          other_display_name: string
          other_handle: string
          other_profile_id: string
          other_type: Database["public"]["Enums"]["profile_type"]
          relationship_id: string
          status: Database["public"]["Enums"]["relationship_status"]
          type: Database["public"]["Enums"]["relationship_type"]
        }[]
      }
      page_items: {
        Args: { p_owner: string; p_viewer: string }
        Returns: {
          audience: Database["public"]["Enums"]["audience"]
          author_profile_id: string
          body: string
          content_type: Database["public"]["Enums"]["content_type"]
          created_at: string
          details: Json
          expires_at: string
          item_id: string
          section: string
          story_label_kind: Database["public"]["Enums"]["story_label_kind"]
          story_label_text: string
          subject_profile_id: string
          top8_position: number
        }[]
      }
      record_profile_view: {
        Args: { p_viewed: string; p_viewer: string }
        Returns: undefined
      }
      relationship_counts: {
        Args: { p_profile_id: string }
        Returns: {
          connections: number
          followers: number
        }[]
      }
      remove_profile_manager: {
        Args: { p_business: string; p_person_profile: string }
        Returns: undefined
      }
      remove_relationship: {
        Args: { p_relationship_id: string }
        Returns: undefined
      }
      request_relationship: {
        Args: {
          p_from: string
          p_to: string
          p_type: Database["public"]["Enums"]["relationship_type"]
        }
        Returns: string
      }
      respond_to_connection: {
        Args: { p_accept: boolean; p_relationship_id: string }
        Returns: undefined
      }
      search_directory: {
        Args: {
          p_city?: string
          p_limit?: number
          p_offset?: number
          p_query: string
          p_searcher?: string
          p_type?: Database["public"]["Enums"]["profile_type"]
        }
        Returns: {
          avatar_path: string
          bio: string
          category: string
          city: string
          country: string
          display_name: string
          dot_colour: Database["public"]["Enums"]["dot_colour"]
          handle: string
          profile_id: string
          rank: number
          search_trust: number
          type: Database["public"]["Enums"]["profile_type"]
          what_i_do: string[]
        }[]
      }
      set_item_audience: {
        Args: {
          p_audience: Database["public"]["Enums"]["audience"]
          p_circle_ids?: string[]
          p_item_id: string
        }
        Returns: undefined
      }
      set_top8: {
        Args: { p_author: string; p_vouch_ids: string[] }
        Returns: undefined
      }
      story_label: {
        Args: { p_story_id: string; p_viewer_profile_id: string }
        Returns: {
          kind: Database["public"]["Enums"]["story_label_kind"]
          label: string
        }[]
      }
      try_uuid: { Args: { p: string }; Returns: string }
      view_as: {
        Args: { p_owner_profile_id: string; p_simulated_viewer: string }
        Returns: {
          audience: Database["public"]["Enums"]["audience"]
          author_profile_id: string
          body: string
          content_type: Database["public"]["Enums"]["content_type"]
          created_at: string
          details: Json
          expires_at: string
          item_id: string
          section: string
          story_label_kind: Database["public"]["Enums"]["story_label_kind"]
          story_label_text: string
          subject_profile_id: string
          top8_position: number
        }[]
      }
    }
    Enums: {
      audience: "public" | "connections" | "circles" | "group"
      content_type: "writing" | "gallery" | "status" | "story"
      dot_colour:
        | "terracotta"
        | "cherry"
        | "mustard"
        | "jade"
        | "lagoon"
        | "violet"
      manager_role: "owner" | "manager"
      notification_type:
        | "connection_request"
        | "connection_accepted"
        | "new_follower"
        | "vouch_received"
        | "profile_viewed"
        | "weekly_search_appearances"
      profile_type: "person" | "business"
      relationship_status: "pending" | "accepted" | "declined"
      relationship_type: "connection" | "follow"
      story_label_kind: "member_label" | "only_for_you" | "shared_with_you"
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
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
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
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
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {
      audience: ["public", "connections", "circles", "group"],
      content_type: ["writing", "gallery", "status", "story"],
      dot_colour: [
        "terracotta",
        "cherry",
        "mustard",
        "jade",
        "lagoon",
        "violet",
      ],
      manager_role: ["owner", "manager"],
      notification_type: [
        "connection_request",
        "connection_accepted",
        "new_follower",
        "vouch_received",
        "profile_viewed",
        "weekly_search_appearances",
      ],
      profile_type: ["person", "business"],
      relationship_status: ["pending", "accepted", "declined"],
      relationship_type: ["connection", "follow"],
      story_label_kind: ["member_label", "only_for_you", "shared_with_you"],
    },
  },
} as const
